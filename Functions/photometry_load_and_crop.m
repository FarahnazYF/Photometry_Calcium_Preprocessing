function raw = photometry_load_and_crop(cfg)
%PHOTOMETRY_LOAD_AND_CROP Load the three raw channels, cut to the analysis window.
%
%   raw = photometry_load_and_crop(cfg)
%
% Loads the photodetector (cfg.pmt_variable) and the two LED monitor
% channels (cfg.led405_variable, cfg.led470_variable) from cfg.input_file
% and keeps only the analysis window: from cfg.hours_before_lights_on hours
% before lights ON, for cfg.duration_hours hours (photometry_crop_indices).
%
% MAT files saved with '-v7.3' are read in part (only the window). Older
% MAT files must be loaded whole first; only the window is kept.
%
% Output
%   raw.pmt, raw.led405, raw.led470  the cropped channels (column vectors)
%   raw.fs                           raw samples per second
%   raw.crop_info                    where the window starts and ends (see
%                                    photometry_crop_indices), plus how the
%                                    recording start was found

fs = cfg.raw_sampling_rate_hz;
names = {cfg.pmt_variable, cfg.led405_variable, cfg.led470_variable};
[first, last, raw.crop_info] = photometry_crop_indices(cfg.recording_start, cfg.lights_on, ...
    fs, cfg.duration_hours, cfg.hours_before_lights_on);
if isfield(cfg, 'recording_start_info')
    raw.crop_info.recording_start_info = cfg.recording_start_info;
end

% ---- Check the three channels exist and are long enough ------------------
vars = whos('-file', cfg.input_file);
n_available = Inf;
for k = 1:numel(names)
    item = vars(strcmp({vars.name}, names{k}));
    if isempty(item)
        error('photometry:Input', ['The MAT file has no variable called "%s".\n' ...
            'Variables in the file: %s\nSet the variable names in Step 1 of the main script.'], ...
            names{k}, strjoin({vars.name}, ', '));
    end
    if sum(item.size > 1) > 1
        error('photometry:Input', '"%s" must be a vector (one row or one column).', names{k});
    end
    n_available = min(n_available, prod(item.size));
end
if first > n_available
    error('photometry:Input', ['The analysis window starts %.2f hours after the recording start, ' ...
        'but the recording is only %.2f hours long. Check the lights ON time.'], ...
        (first-1)/fs/3600, n_available/fs/3600);
end
if isinf(last)
    last = n_available;   % cfg.duration_hours = Inf: keep everything to the end
end
if last > n_available
    error('photometry:Input', ['Only %.2f hours of recording remain after the start of the ' ...
        'analysis window, but cfg.duration_hours = %g.\nSet cfg.duration_hours (Step 1) to %.2f ' ...
        'or less, or to Inf to keep everything to the end.'], ...
        (n_available-first+1)/fs/3600, cfg.duration_hours, floor(100*(n_available-first+1)/fs/3600)/100);
end
raw.crop_info.last_raw_sample = last;
raw.crop_info.duration_hours = (last-first+1)/fs/3600;

% ---- Load ------------------------------------------------------------------
% MAT v7.3 files are HDF5 files and allow reading part of a variable.
fid = fopen(cfg.input_file, 'r');
if fid < 0, error('photometry:Input', 'Cannot open %s.', cfg.input_file); end
header = char(fread(fid, 128, '*char')');
fclose(fid);
fprintf('Loading %s ...\n', cfg.input_file);
channels = cell(1, 3);
if contains(header, 'MATLAB 7.3 MAT-file')
    source = matfile(cfg.input_file);
    for k = 1:3
        item = vars(strcmp({vars.name}, names{k}));
        if item.size(1) == 1
            channels{k} = source.(names{k})(1, first:last);
        else
            channels{k} = source.(names{k})(first:last, 1);
        end
    end
else
    source = load(cfg.input_file, names{:});
    for k = 1:3
        channels{k} = source.(names{k})(first:last);
        source.(names{k}) = [];   % free memory as soon as possible
    end
end
raw.pmt    = double(channels{1}(:));
raw.led405 = double(channels{2}(:));
raw.led470 = double(channels{3}(:));
raw.fs = fs;
fprintf('Loaded %.2f hours (raw samples %d to %d).\n', numel(raw.pmt)/fs/3600, first, last);
end
