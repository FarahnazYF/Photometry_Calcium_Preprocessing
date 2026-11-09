function [clock, info] = photometry_find_recording_start(mat_file, edf_file, fs)
%PHOTOMETRY_FIND_RECORDING_START Clock time of the first raw sample of a recording.
%
%   [clock, info] = photometry_find_recording_start(mat_file)
%   [clock, info] = photometry_find_recording_start(mat_file, edf_file, fs)
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
% Inputs
%   mat_file  full path of the raw MAT recording
%   edf_file  (optional) full path of its EDF file; '' = look next to the MAT
%   fs        (optional, default 1000) raw samples per second; used to check
%             that the EDF really belongs to this MAT file (same length)
%
% Outputs
%   clock  'HH:mm:ss' (with decimals if the EDF stores a fraction of a second)
%   info   where it was found: method, source_file, source_field,
%          recording_start, mat_length_verified
%
% Errors with identifier 'photometry:MissingRecordingStart' when neither
% source has the time (photometry_select_recording then asks you).

if nargin < 2, edf_file = ''; end
if nargin < 3, fs = 1000; end

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

% Check that the MAT file is a complete conversion of this EDF: same
% sampling rate and same number of samples in each raw channel.
if ~isempty(info.edf_raw_sampling_hz)
    if any(abs(info.edf_raw_sampling_hz - fs) > 1e-9)
        error('photometry:EDFRateMismatch', ...
            'The EDF "Raw" channel is sampled at %g Hz, but cfg.raw_sampling_rate_hz = %g Hz.', ...
            info.edf_raw_sampling_hz(1), fs);
    end
    if info.edf_record_count >= 0
        for name = {'Raw', 'Raw_2', 'Raw_3'}
            item = variables(strcmp({variables.name}, name{1}));
            if isempty(item), continue; end   % other channel names: nothing to compare
            if ~any(prod(item.size) == info.edf_expected_raw_samples)
                error('photometry:EDFLengthMismatch', ...
                    ['%s in the MAT file is not as long as the EDF recording. Use the original, ' ...
                     'complete MAT conversion and the EDF file that belongs to it.'], name{1});
            end
            info.mat_length_verified = true;
        end
    end
end
clock = info.recording_start;
end

% ==========================================================================
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
