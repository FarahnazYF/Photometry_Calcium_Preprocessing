function data = photometry_review_artifacts(data, cfg)
%PHOTOMETRY_REVIEW_ARTIFACTS Remove artifacts by hand, one phase at a time.
%
%   data = photometry_review_artifacts(data, cfg)
%
% Runs only if cfg.manual_review is true (you chose "Review" in Step 2).
% For each phase a figure opens with
%   left axis  (green): the preliminary motion-corrected 470 (Step 9)
%   red dots          : the automatic artifact suggestions (Step 9)
%   right axis (blue) : the bleaching-corrected 405
% What to do:
%   1. Zoom in if needed (magnifier icons in the figure's toolbar), then
%      choose the Brush tool if it is not already active.
%   2. Drag a rectangle over the bad stretches of the GREEN (470) trace.
%      Hold Shift to add more stretches.
%   3. Click Apply  -> the selected stretches become missing (NaN) in BOTH
%                      channels and are not used in Step 11.
%      Click Skip   -> nothing changes in this phase (closing the figure
%                      does the same).
%      Click Done   -> stop reviewing; the remaining phases are not changed.
% Each selected stretch is removed from its first to its last selected
% sample.
%
% Output
%   data.manual_mask     true where you removed samples
%   data.manual_windows  one row per removed stretch: phase, start and end in
%                        seconds from the start of the analysis window, and
%                        the day and Zeitgeber time (0-24) of its start and
%                        end (see photometry_zt)
% Running this step again starts the review from scratch.

window_columns = {'phase', 'start_s', 'end_s', 'start_day', 'start_zt_hours', 'end_day', 'end_zt_hours'};
n = numel(data.time_s);
data.manual_mask = false(n, 1);
data.manual_windows = table('Size', [0 numel(window_columns)], ...
    'VariableTypes', repmat({'double'}, 1, numel(window_columns)), 'VariableNames', window_columns);
data = photometry_note_step(data, 10, cfg, {'manual_review'});
if ~cfg.manual_review
    fprintf('Manual artifact removal skipped.\n');
    return;
end

for p = 1:size(data.phase_windows, 1)
    [mask, action] = review_one_phase(data, p);
    if any(mask)
        data.manual_mask = data.manual_mask | mask;
        data.manual_windows = [data.manual_windows; windows_from_mask(mask, p, data)];
    end
    if action == "done", break; end
end
fprintf('Manual artifact removal: %d stretches, %.1f s in total.\n', ...
    height(data.manual_windows), nnz(data.manual_mask)/cfg.sample_rate_hz);
end

% ==========================================================================
function [mask, action] = review_one_phase(data, p)
% Show one phase, wait for Apply / Skip / Done, return the selected samples.
n = numel(data.time_s);
mask = false(n, 1);
idx = (data.phase_windows(p, 1):data.phase_windows(p, 2))';
t_min = (data.time_s(idx) - data.time_s(idx(1)))/60;      % minutes since phase start
h0 = data.crop_info.start_hours_from_lights_on;            % time zero in hours from the first lights ON
[~, ~, from] = photometry_zt(h0 + data.time_s(idx(1))/3600);
[~, ~, to] = photometry_zt(h0 + data.time_s(idx(end))/3600);

fig = figure('Color', 'w', 'Name', sprintf('Manual artifact removal - %s', data.phase_names{p}), ...
    'NumberTitle', 'off');
ax = axes('Parent', fig, 'Position', [0.08 0.11 0.84 0.74]);
hold(ax, 'on');
yyaxis(ax, 'left');
h470 = plot(ax, t_min, data.preliminary_residual(idx), 'Color', [0 0.6 0], 'LineWidth', 1);
suggested = data.artifact_suggestion_mask(idx);
plot(ax, t_min(suggested), data.preliminary_residual(idx(suggested)), 'r.', 'MarkerSize', 6);
ylabel(ax, '470, motion-corrected (preliminary)');
yyaxis(ax, 'right');
plot(ax, t_min, data.corrected405(idx), 'Color', [0 0.3 0.9], 'LineWidth', 0.8);
ylabel(ax, '405, bleaching-corrected');
xlabel(ax, 'Minutes since the start of this phase');
grid(ax, 'on');
title(ax, sprintf('%s (%s to %s): select bad stretches of the green trace, then Apply', ...
    data.phase_names{p}, from, to));

uicontrol(fig, 'Style', 'text', 'Units', 'normalized', 'Position', [0.01 0.93 0.70 0.06], ...
    'BackgroundColor', 'w', 'HorizontalAlignment', 'left', 'String', ...
    ['Brush (drag) over artifacts on the GREEN trace; red dots = automatic suggestions. ' ...
     'Apply = remove the selection from both channels. Skip = no change. Done = stop reviewing.']);
uicontrol(fig, 'Style', 'pushbutton', 'Units', 'normalized', 'Position', [0.74 0.945 0.08 0.045], ...
    'String', 'Apply', 'Callback', @(~, ~) finish(fig, 'apply'));
uicontrol(fig, 'Style', 'pushbutton', 'Units', 'normalized', 'Position', [0.83 0.945 0.08 0.045], ...
    'String', 'Skip', 'Callback', @(~, ~) finish(fig, 'skip'));
uicontrol(fig, 'Style', 'pushbutton', 'Units', 'normalized', 'Position', [0.92 0.945 0.07 0.045], ...
    'String', 'Done', 'Callback', @(~, ~) finish(fig, 'done'));

setappdata(fig, 'user_action', 'skip');
fig.CloseRequestFcn = @(~, ~) close_as_skip(fig);    % closing the window = Skip
drawnow;
brush(fig, 'on');
uiwait(fig);                                          % wait for a button

if ~isvalid(fig)                                      % the window was closed
    action = "skip";
    return;
end
action = string(getappdata(fig, 'user_action'));
if action == "apply"
    brushed = h470.BrushData;
    if ~isempty(brushed) && any(brushed)
        selected = find(logical(brushed(:)));        % positions within this phase
        % Each run of consecutive selected samples is one stretch, removed
        % from its first to its last sample.
        breaks = find(diff(selected) > 1);
        first = selected([1; breaks+1]);
        last  = selected([breaks; numel(selected)]);
        for k = 1:numel(first)
            mask(idx(first(k):last(k))) = true;
        end
    end
end
delete(fig);
end

function windows = windows_from_mask(mask, p, data)
% One table row per run of consecutive true samples.
edges = diff([false; mask(:); false]);
first = find(edges == 1);
last = find(edges == -1) - 1;
h0 = data.crop_info.start_hours_from_lights_on;            % time zero in hours from the first lights ON
[start_zt, start_day] = photometry_zt(h0 + data.time_s(first)/3600);
[end_zt, end_day] = photometry_zt(h0 + data.time_s(last)/3600);
windows = table(repmat(p, numel(first), 1), data.time_s(first), data.time_s(last), ...
    start_day, start_zt, end_day, end_zt, 'VariableNames', ...
    {'phase', 'start_s', 'end_s', 'start_day', 'start_zt_hours', 'end_day', 'end_zt_hours'});
end

function finish(fig, action)
setappdata(fig, 'user_action', action);
uiresume(fig);
end

function close_as_skip(fig)
setappdata(fig, 'user_action', 'skip');
uiresume(fig);
delete(fig);
end
