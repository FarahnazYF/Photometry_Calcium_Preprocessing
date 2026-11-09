function info = photometry_read_edf_start(filename)
%PHOTOMETRY_READ_EDF_START Read the recording start time from an EDF header.
%
%   info = photometry_read_edf_start(filename)
%
% Reads only the EDF header (and, for EDF+, the first time-keeping
% annotation), never the signals, so it is fast even for large files.
%   EDF:  the start date and time are stored as text in the fixed header
%         (https://www.edfplus.info/specs/edf.html).
%   EDF+: the first data record may start a fraction of a second after that
%         time; the offset is read from the annotation channel
%         (https://www.edfplus.info/specs/edfplus.html).
%
% Output fields
%   recording_start              'HH:mm:ss' (with decimals if needed)
%   method, source_file, source_field   where the time came from
%   edf_header_start_date/_time  the raw header text
%   edf_first_record_offset_sec  EDF+ offset of the first record (0 for EDF)
%   edf_format                   'EDF+C', 'EDF+D' or '' (plain EDF)
%   edf_record_count, edf_record_duration_sec
%   edf_raw_sampling_hz          sampling rate of a channel labelled 'Raw' ([] if none)
%   edf_expected_raw_samples     number of samples of that channel
%   mat_length_verified          false (photometry_find_recording_start checks it)

fid = fopen(filename, 'r', 'ieee-le');
if fid < 0, error('photometry:EDFHeader', 'Cannot open the EDF file: %s', filename); end
cleanup = onCleanup(@() fclose(fid));

% ---- Fixed 256-byte header -----------------------------------------------
header = char(fread(fid, 256, '*uint8')');
if numel(header) ~= 256 || ~strcmp(strtrim(header(1:8)), '0')
    error('photometry:EDFHeader', 'This is not a valid EDF file: %s', filename);
end
date_text = strtrim(header(169:176));   % dd.mm.yy
time_text = strtrim(header(177:184));   % hh.mm.ss
if isempty(regexp(date_text, '^\d{2}\.\d{2}\.\d{2}$', 'once')) || ...
        isempty(regexp(time_text, '^\d{2}\.\d{2}\.\d{2}$', 'once'))
    error('photometry:EDFHeader', 'The EDF start date/time is missing or invalid.');
end
clock = strrep(time_text, '.', ':');
photometry_crop_indices(clock, '08:00', 1, 1);   % checks the clock is valid
header_bytes    = str2double(header(185:192));
reserved        = strtrim(header(193:236));
record_count    = str2double(header(237:244));
record_duration = str2double(header(245:252));
n_signals       = str2double(header(253:256));
if ~isfinite(n_signals) || n_signals < 1 || n_signals ~= fix(n_signals) || n_signals > 4096 || ...
        ~isfinite(header_bytes) || header_bytes < 256*(1+n_signals) || ...
        ~isfinite(record_duration) || record_duration <= 0 || ...
        ~isfinite(record_count) || record_count < -1 || record_count ~= fix(record_count)
    error('photometry:EDFHeader', 'The EDF signal count, header size or record duration is invalid.');
end

% ---- Signal headers (256 bytes per signal) --------------------------------
signal_header = char(fread(fid, 256*n_signals, '*uint8')');
if numel(signal_header) ~= 256*n_signals
    error('photometry:EDFHeader', 'The EDF signal header is incomplete.');
end
labels = strtrim(cellstr(reshape(signal_header(1:16*n_signals), 16, [])'));
sample_text = signal_header(216*n_signals+1:224*n_signals);
samples = str2double(cellstr(reshape(sample_text, 8, [])'));   % samples per record, per signal
if any(~isfinite(samples) | samples < 1 | samples ~= fix(samples))
    error('photometry:EDFHeader', 'The EDF samples-per-record values are invalid.');
end

% ---- EDF+: offset of the first data record ---------------------------------
first_record_offset = 0;
if startsWith(reserved, 'EDF+')
    annotation = find(strcmp(labels, 'EDF Annotations'), 1);
    if isempty(annotation)
        error('photometry:EDFHeader', 'This EDF+ file has no time-keeping annotation channel.');
    end
    offset = header_bytes + 2*sum(samples(1:annotation-1));
    if fseek(fid, offset, 'bof') ~= 0
        error('photometry:EDFHeader', 'Cannot read the first EDF+ time-keeping annotation.');
    end
    % The first number is the onset of the first record, in seconds after
    % the header time (it may include a fraction of a second).
    bytes = fread(fid, min(2*samples(annotation), 256), '*uint8')';
    separator = find(bytes == 20, 1);
    if isempty(separator)
        error('photometry:EDFHeader', 'The EDF+ time-keeping onset is missing.');
    end
    onset = char(bytes(1:separator-1));
    if isempty(regexp(onset, '^[+-]\d+(\.\d+)?$', 'once'))
        error('photometry:EDFHeader', 'The EDF+ time-keeping onset is not a signed number.');
    end
    first_record_offset = str2double(onset);
end

% ---- Start time of the first sample ----------------------------------------
parts = str2double(strsplit(clock, ':'));
seconds = mod(parts(1)*3600 + parts(2)*60 + parts(3) + first_record_offset, 86400);
hh = floor(seconds/3600); mm = floor(mod(seconds, 3600)/60); ss = mod(seconds, 60);
if ss == fix(ss)
    clock = sprintf('%02d:%02d:%02d', hh, mm, ss);
else
    clock = sprintf('%02d:%02d:%09.6f', hh, mm, ss);
end

info.method = 'EDF file header';
info.source_file = char(filename);
info.source_field = 'EDF start date/time and first EDF+ record onset';
info.recording_start = clock;
info.edf_header_start_date = date_text;
info.edf_header_start_time = time_text;
info.edf_first_record_offset_sec = first_record_offset;
info.edf_format = reserved;
info.edf_record_count = record_count;
info.edf_record_duration_sec = record_duration;
raw = strcmpi(labels, 'Raw');
info.edf_raw_sampling_hz = samples(raw)/record_duration;
info.edf_expected_raw_samples = record_count*samples(raw);
info.mat_length_verified = false;
end
