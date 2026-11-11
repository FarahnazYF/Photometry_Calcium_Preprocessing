function data = photometry_note_step(data, step, cfg, names)
%PHOTOMETRY_NOTE_STEP Record the settings a step used; mark later steps as out of date.
%
%   data = photometry_note_step(data, step, cfg, names)
%
% Every processing function (Steps 4 to 11) calls this once, at its end.
%
% 1. It copies the settings the step used (the fields of cfg listed in
%    names) into data.applied_settings. The saved results list these
%    values, so they describe what was really applied to the data, even if
%    cfg was changed afterwards.
% 2. It marks this step as done and every LATER step as not done
%    (data.steps_done). If one section of the main script is run again,
%    the sections after it must be run again too. Step 14 checks this and
%    refuses to save results that mix old and new calculations.
%
% Inputs
%   data   the data structure of the pipeline
%   step   the number of the step in run_calcium_preprocessing.m (4 to 11)
%   cfg    the settings
%   names  cell array with the names of the settings (fields of cfg) used

for k = 1:numel(names)
    data.applied_settings.(names{k}) = cfg.(names{k});
end
if ~isfield(data, 'steps_done'), data.steps_done = false(1, 11); end
data.steps_done(step) = true;
data.steps_done(step+1:end) = false;
end
