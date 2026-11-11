function cfg = photometry_select_recording(cfg)
%PHOTOMETRY_SELECT_RECORDING Ask for the raw file and lights ON; read the recording start.
%
%   cfg = photometry_select_recording(cfg)
%
% Dialogs, in this order:
%   1. Choose the raw MAT recording. It must contain the photodetector and
%      the two LED monitor channels named in the settings
%      (cfg.pmt_variable, cfg.led405_variable, cfg.led470_variable).
%   2. Type the time the lights turn ON (24-hour clock, e.g. 07:00).
%   3. The clock time of the first raw sample (the "recording start") is
%      read automatically: first from the MAT file, otherwise from the EDF
%      file with the same name in the same folder. If neither stores it,
%      you can choose the EDF file yourself or type the start time.
%      (Skipped when cfg.recording_start is set in the settings.)
%      An EDF file is checked against the MAT file (same length); see
%      photometry_find_recording_start.
%   4. A preview shows the start time, whether it was checked, and where
%      the recording will be cut. Click Continue.
%   5. Choose whether to remove artifacts by hand (Step 10).
%
% Returns cfg with these fields added, or [] if you click Cancel:
%   input_file, data_folder, filebase, lights_on, recording_start,
%   recording_start_info, manual_review, output_folder

% ---- 1. The raw recording ------------------------------------------------
prompt = sprintf('Choose the RAW recording (a MAT file with %s, %s and %s)', ...
    cfg.pmt_variable, cfg.led405_variable, cfg.led470_variable);
[name, folder] = uigetfile({'*.mat', 'MATLAB recording (*.mat)'}, prompt);
if isequal(name, 0), cfg = []; return; end
cfg.input_file  = fullfile(folder, name);
cfg.data_folder = folder;
[~, cfg.filebase] = fileparts(name);

% ---- 2. Lights ON ---------------------------------------------------------
lights_on = ask_clock('Lights ON time (24-hour clock, HH:mm; for example 07:00 or 08:00):', ...
    'Light schedule', cfg.lights_on);
if isempty(lights_on), cfg = []; return; end
cfg.lights_on = lights_on;

% ---- 3. Recording start ---------------------------------------------------
if ~isempty(cfg.recording_start)
    % Set by hand in the settings: check the format, then use it.
    photometry_crop_indices(cfg.recording_start, '08:00', 1, 1);
    cfg.recording_start_info = start_info('set in the settings (cfg.recording_start)', ...
        cfg.recording_start, 'Set by hand in the settings (not checked).');
else
    edf_file = '';
    channel_names = {cfg.pmt_variable, cfg.led405_variable, cfg.led470_variable};
    while true
        try
            [cfg.recording_start, cfg.recording_start_info] = photometry_find_recording_start( ...
                cfg.input_file, edf_file, cfg.raw_sampling_rate_hz, channel_names);
            break;
        catch err
            if ~strcmp(err.identifier, 'photometry:MissingRecordingStart')
                % A real problem (e.g. an EDF that does not belong to this MAT file).
                uiwait(errordlg(err.message, 'Recording start could not be read', 'modal'));
                cfg = []; return;
            end
            choice = questdlg(sprintf(['The MAT file does not store the clock time of its first ' ...
                'sample, and no EDF file with the same name was found next to it.\n\n' ...
                'Choose the original EDF file of this recording, or type the start time.']), ...
                'Recording start time', 'Choose EDF file', 'Type the time', 'Cancel', 'Choose EDF file');
            switch choice
                case 'Choose EDF file'
                    [edf_name, edf_folder] = uigetfile(fullfile(folder, '*.edf'), ...
                        'Choose the ORIGINAL EDF file of this recording');
                    if isequal(edf_name, 0), cfg = []; return; end
                    edf_file = fullfile(edf_folder, edf_name);
                case 'Type the time'
                    typed = ask_clock('Clock time of the FIRST raw sample (24-hour, HH:mm:ss):', ...
                        'Recording start', '');
                    if isempty(typed), cfg = []; return; end
                    cfg.recording_start = typed;
                    cfg.recording_start_info = start_info('typed in the dialog', typed, ...
                        'Typed by hand (not checked).');
                    break;
                otherwise
                    cfg = []; return;
            end
        end
    end
end

% ---- 4. Preview of the crop ----------------------------------------------
[~, ~, crop] = photometry_crop_indices(cfg.recording_start, cfg.lights_on, ...
    cfg.raw_sampling_rate_hz, cfg.duration_hours, cfg.hours_before_lights_on);
if isinf(cfg.duration_hours)
    keep_text = 'Keep everything until the end of the recording.';
else
    keep_text = sprintf('Keep %g hours.', cfg.duration_hours);
end
[~, ~, start_label] = photometry_zt(crop.start_hours_from_lights_on);
% Was the start time checked against the MAT file? An EDF file that could
% not be checked gets a warning: a start time from the wrong EDF file would
% shift the analysis window and every Zeitgeber time.
check_text = cfg.recording_start_info.verification_note;
from_edf = startsWith(cfg.recording_start_info.method, 'EDF');
if from_edf && ~cfg.recording_start_info.mat_length_verified
    check_text = sprintf('WARNING: %s\nMake sure this EDF file belongs to this recording.', check_text);
end
message = sprintf(['Recording start: %s\n(read from: %s)\n%s\n\n' ...
    'Lights ON: %s (= ZT 0)\n' ...
    'The analysis starts at %s, %g hour(s) before lights ON (%s).\n' ...
    'The first %.2f minutes of the recording are not used.\n%s'], ...
    cfg.recording_start, cfg.recording_start_info.method, check_text, cfg.lights_on, ...
    crop.reference_clock, cfg.hours_before_lights_on, start_label, ...
    crop.offset_sec/60, keep_text);
if crop.offset_sec > 12*3600
    % The target time had already passed when the recording started, so the
    % crop begins on the following day. Usually a typing mistake.
    message = sprintf(['%s\n\nWARNING: more than 12 hours are skipped. The recording started ' ...
        'after %s, so the analysis starts on the NEXT day. Check the lights ON time.'], ...
        message, crop.reference_clock);
end
choice = questdlg(message, 'Check where the recording is cut', 'Continue', 'Cancel', 'Continue');
if ~strcmp(choice, 'Continue'), cfg = []; return; end

% ---- 5. Manual artifact removal? -----------------------------------------
choice = questdlg(sprintf(['Remove artifacts by hand?\n\nOne figure per phase will open. ' ...
    'Drag over bad stretches of the 470 trace and click Apply.']), ...
    'Manual artifact removal', 'Review', 'Skip review', 'Review');
if isempty(choice), cfg = []; return; end
cfg.manual_review = strcmp(choice, 'Review');

% ---- Results folder ------------------------------------------------------
% A new, time-stamped folder for every run, so earlier results are never
% overwritten.
root = cfg.output_root;
if isempty(root), root = fullfile(folder, 'calcium_preprocessing_results'); end
stamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
cfg.output_folder = fullfile(root, [cfg.filebase '_' stamp]);

% Windows cannot save files whose full path is longer than 259 characters.
% Check now rather than after hours of processing.
files = photometry_output_files(cfg);
if files.longest_path > 259
    message = sprintf(['The results would be saved in a folder whose path is too long for ' ...
        'Windows (%d of at most 259 characters):\n\n%s\n\n' ...
        'Set cfg.output_root in the settings (Step 1) to a shorter folder, ' ...
        'for example ''C:\\results''.'], files.longest_path, cfg.output_folder);
    uiwait(errordlg(message, 'Results folder path too long', 'modal'));
    cfg = []; return;
end

fprintf('Recording : %s\n', cfg.input_file);
fprintf('Start     : %s (%s)\n', cfg.recording_start, cfg.recording_start_info.method);
fprintf('            %s\n', strrep(check_text, newline, ' '));
fprintf('Lights ON : %s | analysis starts at %s (%s); %.2f minutes skipped.\n', ...
    cfg.lights_on, crop.reference_clock, start_label, crop.offset_sec/60);
fprintf('Results   : %s\n\n', cfg.output_folder);
end

% ==========================================================================
function value = ask_clock(question, title, default)
% Ask for a clock time until it is valid; '' if the user cancels.
value = '';
while true
    answer = inputdlg({question}, title, [1 75], {default});
    if isempty(answer), return; end
    try
        photometry_crop_indices(strtrim(answer{1}), '08:00', 1, 1);   % checks the format
        value = strtrim(answer{1});
        return;
    catch err
        uiwait(errordlg(err.message, 'Check the time', 'modal'));
        default = answer{1};
    end
end
end

function info = start_info(method, clock, note)
% The same fields as photometry_find_recording_start returns.
info.method = method;
info.source_file = '';
info.source_field = '';
info.recording_start = clock;
info.mat_length_verified = false;
info.verification_note = note;
end
