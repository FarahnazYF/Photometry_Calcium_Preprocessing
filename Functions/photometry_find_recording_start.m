function [clock, info] = photometry_find_recording_start(mat_file, edf_file, fs, channel_names)
%PHOTOMETRY_FIND_RECORDING_START Clock time of the first raw sample of a recording.
%
%   [clock, info] = photometry_find_recording_start(mat_file)
%   [clock, info] = photometry_find_recording_start(mat_file, edf_file, fs, channel_names)
%
% Where the time comes from, in this order:
%   1. A small variable in the MAT file that stores the start time, for
%      example RecordingStartTime = '06:56:16' (also inside a struct called
%      header, metadata, ...). Large signal arrays are never loaded.
%   2. Otherwise the header of the original EDF file: edf_file if given,
%      else the EDF with the same name in the same folder as the MAT file
%      (e.g. Mouse1.0001.mat -> Mouse1.0001.edf).
% The time is never guessed from file dates or signal values.
%
% Check of an EDF file
%   The start time of an EDF file is only right for the MAT file if the
%   MAT file is a complete copy of that EDF recording. This is checked:
%   - If the EDF has a channel with the name of a MAT channel (for example
%     "Raw"), the two must have the same sampling rate and the same number
%     of samples. MATLAB adds _2, _3 to repeated names, so the MAT variable
%     "Raw_2" is also compared with an EDF channel called "Raw".
%   - Otherwise the two recordings must be equally long (to within one EDF
%     data record).
%   A mismatch is an error. If no check is possible (the EDF does not say
%   how long the recording is), the time is still returned, but
%   info.mat_length_verified is false and info.verification_note says why.
%   The dialog of Step 2 then shows a warning.
%
% Inputs
%   mat_file       full path of the raw MAT recording
%   edf_file       (optional) full path of its EDF file; '' = look next to the MAT
%   fs             (optional, default 1000) raw samples per second
%   channel_names  (optional, default {'Raw','Raw_2','Raw_3'}) names of the
%                  photodetector and LED monitor variables in the MAT file
%
% Outputs
%   clock  'HH:mm:ss' (with decimals if the EDF stores a fraction of a second)
%   info   where it was found: method, source_file, source_field,
%          recording_start, mat_length_verified, verification_note
%
% Errors with identifier 'photometry:MissingRecordingStart' when neither
% source has the time (photometry_select_recording then asks you).

if nargin < 2, edf_file = ''; end
if nargin < 3 || isempty(fs), fs = 1000; end
if nargin < 4 || isempty(channel_names), channel_names = {'Raw', 'Raw_2', 'Raw_3'}; end

% ---- 1. Look for a start-time variable inside the MAT file --------------
variables = whos('-file', mat_file);
known = {'recordingstartdatetime', 'recordingstarttime', 'recordingstart', ...
    'startdatetime', 'starttime', 'startdate'};
containers = {'header', 'hdr', 'metadata', 'recordinginfo', 'recordingmetadata', 'edfheader', 'recording'};
clocks = {}; fields = {};
for k = 1:numel(variables)
    name = variables(k).name;
    key = lower(strrep(name, '_', ''));
    % Only small variables with a start-time-like name are loaded.
    if variables(k).bytes > 1024*1024 || ~any(strcmp(key, [known, containers]))
        continue;
    end
    loaded = load(mat_file, name);
    [found, paths] = inspect(loaded.(name), name, key, 0, known, containers);
    clocks = [clocks, found]; fields = [fields, paths]; %#ok<AGROW>
end
if ~isempty(clocks)
    % Several fields must agree (compared in seconds, so 06:56 = 06:56:00).
    seconds = zeros(size(clocks));
    for k = 1:numel(clocks)
        [~, ~, crop] = photometry_crop_indices(clocks{k}, '01:00', 1, 1);
        seconds(k) = mod(-crop.offset_sec, 86400);
    end
    if any(abs(seconds - seconds(1)) > 1e-6)
        error('photometry:ConflictingStart', ...
            'The start-time fields in the MAT file disagree (%s). Fix them before cropping.', ...
            strjoin(fields, ', '));
    end
    clock = clocks{1};
    info.method = 'MAT file (start-time variable)';
    info.source_file = char(mat_file);
    info.source_field = strjoin(fields, ', ');
    info.recording_start = clock;
    info.mat_length_verified = false;
    info.verification_note = 'Stored in the MAT file itself.';
    return;
end

% ---- 2. Otherwise read the EDF header ------------------------------------
if isempty(edf_file)
    [folder, stem] = fileparts(mat_file);
    edf_file = fullfile(folder, [stem '.edf']);
end
if ~isfile(edf_file)
    error('photometry:MissingRecordingStart', ...
        ['The MAT file stores no recording start time, and no EDF file with the same ' ...
         'name was found next to it (%s).'], edf_file);
end
info = photometry_read_edf_start(edf_file);
if startsWith(info.edf_format, 'EDF+D')
    error('photometry:DiscontinuousEDF', ...
        ['This EDF file has gaps in its recording ("EDF+D"). Clock times cannot be ' ...
         'recovered from sample numbers across those gaps.']);
end
[info.mat_length_verified, info.verification_note] = compare_edf_with_mat( ...
    info, variables, channel_names, fs);
clock = info.recording_start;
end

% ==========================================================================
function [verified, note] = compare_edf_with_mat(info, variables, channel_names, fs)
% Is the MAT file a complete copy of this EDF recording? Errors if it is
% clearly not; verified = false (with a note) if this cannot be told.
verified = false;
if info.edf_record_count < 0
    note = 'NOT CHECKED against the MAT file: the EDF file does not say how long the recording is.';
    return;
end

% Channels that have the same name in both files.
checked = {};
for k = 1:numel(channel_names)
    item = variables(strcmp({variables.name}, channel_names{k}));
    if isempty(item), continue; end
    same_name = unique({channel_names{k}, regexprep(channel_names{k}, '_\d+$', '')});
    match = ismember(lower(info.edf_labels), lower(same_name));
    if ~any(match), continue; end
    rate = info.edf_samples_per_record(match)/info.edf_record_duration_sec;
    if ~any(abs(rate - fs) <= 1e-9)
        error('photometry:EDFRateMismatch', ...
            'The EDF channel "%s" is sampled at %g Hz, but cfg.raw_sampling_rate_hz = %g Hz.', ...
            channel_names{k}, rate(1), fs);
    end
    expected = info.edf_record_count*info.edf_samples_per_record(match);
    if ~any(prod(item.size) == expected)
        error('photometry:EDFLengthMismatch', ...
            ['%s in the MAT file is not as long as the EDF recording. Use the original, ' ...
             'complete MAT conversion and the EDF file that belongs to it.'], channel_names{k});
    end
    checked{end+1} = channel_names{k}; %#ok<AGROW>
end
if ~isempty(checked)
    verified = true;
    note = sprintf('The MAT file matches the EDF file (%s: same number of samples).', strjoin(checked, ', '));
    return;
end

% No channel has the same name in both files: compare the two durations.
item = variables(strcmp({variables.name}, channel_names{1}));
if isempty(item)
    note = sprintf('NOT CHECKED against the MAT file: it has no variable called "%s".', channel_names{1});
    return;
end
duration_mat = prod(item.size)/fs;
duration_edf = info.edf_record_count*info.edf_record_duration_sec;
if abs(duration_mat - duration_edf) > info.edf_record_duration_sec
    error('photometry:EDFLengthMismatch', ...
        ['The MAT recording is %.3f hours long ("%s" at %g Hz), but the EDF recording is %.3f hours ' ...
         'long. Use the original, complete MAT conversion and the EDF file that belongs to it.'], ...
        duration_mat/3600, channel_names{1}, fs, duration_edf/3600);
end
verified = true;
note = 'The MAT file matches the EDF file (the two recordings are equally long; the channel names differ).';
end

function [clocks, paths] = inspect(value, path, key, depth, known, containers)
% Search a loaded variable (and structs inside it, up to 3 levels) for a
% start-time value. Returns every clock found and where it was found.
clocks = {}; paths = {};
if isstruct(value) && isscalar(value) && depth < 3
    names = fieldnames(value);
    for k = 1:numel(names)
        child = lower(strrep(names{k}, '_', ''));
        if any(strcmp(child, [known, containers]))
            [c, p] = inspect(value.(names{k}), [path '.' names{k}], child, depth+1, known, containers);
            clocks = [clocks, c]; paths = [paths, p]; %#ok<AGROW>
        end
    end
    return;
end
if ~any(strcmp(key, known)), return; end
clock = '';
if isdatetime(value) && isscalar(value) && ~isnat(value)
    value.Format = 'HH:mm:ss.SSSSSS';
    clock = char(value);
elseif (ischar(value) && isrow(value)) || (isstring(value) && isscalar(value) && ~ismissing(value))
    text = strtrim(char(value));
    if ~isempty(regexp(text, '^\d{1,2}:\d{2}(:\d{2}(\.\d+)?)?$', 'once'))
        clock = text;                                   % 06:56:16
    elseif ~isempty(regexp(text, '^\d{2}\.\d{2}\.\d{2}$', 'once')) && ~strcmp(key, 'startdate')
        clock = strrep(text, '.', ':');                 % 06.56.16 (EDF style)
    else
        % 2026-10-01 06:56:16 or 2026-10-01T06:56:16 (a date alone is not a clock)
        token = regexp(text, '^\d{4}-\d{2}-\d{2}[ T](\d{2}:\d{2}:\d{2}(?:\.\d+)?)$', 'tokens', 'once');
        if ~isempty(token), clock = token{1}; end
    end
end
if ~isempty(clock)
    photometry_crop_indices(clock, '08:00', 1, 1);   % errors if the clock is invalid
    clocks = {clock}; paths = {path};
end
end
