function files = photometry_output_files(cfg)
%PHOTOMETRY_OUTPUT_FILES Full paths of every file the pipeline writes.
%
%   files = photometry_output_files(cfg)
%
% All results go into cfg.output_folder, a new time-stamped folder per run.
% File names start with the recording name (cfg.filebase):
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

base = fullfile(cfg.output_folder, cfg.filebase);
files.folder               = cfg.output_folder;
files.mat                  = [base '_calcium_preprocessed.mat'];
files.phase_summary        = [base '_phase_summary.csv'];
files.artifact_suggestions = [base '_artifact_suggestions.csv'];
files.manual_windows       = [base '_manual_removed_windows.csv'];
files.sawtooth_windows     = [base '_sawtooth_windows.csv'];
files.trace_csv            = [base '_trace.csv'];
files.figures_folder       = fullfile(cfg.output_folder, 'figures');

% The longest figure file name is about 45 characters.
paths = struct2cell(files);
files.longest_path = max([cellfun(@numel, paths); numel(files.figures_folder) + 46]);
end
