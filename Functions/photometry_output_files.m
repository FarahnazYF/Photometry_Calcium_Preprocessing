function files = photometry_output_files(cfg)
%PHOTOMETRY_OUTPUT_FILES Full paths of every file the pipeline writes.
%
%   files = photometry_output_files(cfg)
%
% All results go into cfg.output_folder, a new time-stamped folder per run.
%
% A folder that already holds saved results is never written to again. If
% you save a second time in the same MATLAB session (for example after
% running some sections of the main script again), the new results and the
% figures of the sections you ran again go to <folder>_2, then <folder>_3,
% and so on. files.save_number says which one this is (1 = the first).
%
% File names start with the recording name (cfg.filebase):
%   files.folder                the folder that is written to now
%   files.mat                   <recording>_calcium_preprocessed.mat
%   files.phase_summary         <recording>_phase_summary.csv
%   files.artifact_suggestions  <recording>_artifact_suggestions.csv
%   files.manual_windows        <recording>_manual_removed_windows.csv
%   files.sawtooth_windows      <recording>_sawtooth_windows.csv
%   files.trace_csv             <recording>_trace.csv (only if cfg.save_trace_csv)
%   files.figures_folder        figures\ (only if cfg.save_figures)
%   files.longest_path          length of the longest of these paths. Windows
%                               cannot save a file whose path is longer than
%                               259 characters.

% The first folder in the row <folder>, <folder>_2, <folder>_3, ... that
% does not hold a saved results file yet.
mat_name = [cfg.filebase '_calcium_preprocessed.mat'];
folder = cfg.output_folder;
save_number = 1;
while isfile(fullfile(folder, mat_name))
    save_number = save_number + 1;
    folder = sprintf('%s_%d', cfg.output_folder, save_number);
end

base = fullfile(folder, cfg.filebase);
files.folder               = folder;
files.mat                  = fullfile(folder, mat_name);
files.phase_summary        = [base '_phase_summary.csv'];
files.artifact_suggestions = [base '_artifact_suggestions.csv'];
files.manual_windows       = [base '_manual_removed_windows.csv'];
files.sawtooth_windows     = [base '_sawtooth_windows.csv'];
files.trace_csv            = [base '_trace.csv'];
files.figures_folder       = fullfile(folder, 'figures');

% The longest figure file name is about 45 characters.
paths = struct2cell(files);
files.longest_path = max([cellfun(@numel, paths); numel(files.figures_folder) + 46]);
files.save_number = save_number;
end
