function line_handle = photometry_plot_zoomable(ax, time, signal, max_points, varargin)
%PHOTOMETRY_PLOT_ZOOMABLE A long trace that shows every sample once you zoom in.
%
%   h = photometry_plot_zoomable(ax, time, signal, max_points, ...plot options...)
%
% Zoomed out, the trace is drawn like photometry_plot_trace (lowest and
% highest value of short blocks). Whenever the visible time range holds at
% most max_points samples (about 6.5 minutes at 50 Hz with the default
% 20,000), the line is redrawn with EVERY sample in view, so close-ups show
% the true shape. Zooming back out restores the overview.
%
% time must be a vector (one value per sample) in the units of the x axis.
% The full trace is stored with the line, so use this for a few figures
% only (it uses memory).

line_handle = photometry_plot_trace(ax, time, signal, max_points, varargin{:});
if isscalar(time) || numel(signal) <= max_points, return; end

store.t = time(:);
store.y = signal(:);
store.max_points = max_points;
store.overview_x = line_handle.XData;
store.overview_y = line_handle.YData;
intervals = diff(store.t(1:min(end, 10000)));
store.gap = 1.5*median(intervals(intervals > 0));
line_handle.UserData = store;

% One listener per axes redraws all its zoomable lines when the x range changes.
managed = getappdata(ax, 'photometry_zoomable_lines');
if isempty(managed)
    addlistener(ax, 'XLim', 'PostSet', @(~, ~) redraw(ax));
    managed = gobjects(0);
end
setappdata(ax, 'photometry_zoomable_lines', [managed line_handle]);
end

% ==========================================================================
function redraw(ax)
if ~isvalid(ax), return; end
managed = getappdata(ax, 'photometry_zoomable_lines');
managed = managed(isvalid(managed));
limits = ax.XLim;
for h = managed
    s = h.UserData;
    first = find(s.t >= limits(1), 1);
    last = find(s.t <= limits(2), 1, 'last');
    if isempty(first) || isempty(last) || last < first || last-first+1 > s.max_points
        % Too many samples in view: show the overview.
        if numel(h.XData) ~= numel(s.overview_x)
            set(h, 'XData', s.overview_x, 'YData', s.overview_y);
        end
        continue;
    end
    keep = max(1, first-1):min(numel(s.t), last+1);   % one sample beyond each edge
    x = s.t(keep);
    y = s.y(keep);
    jumps = find(diff(x) > s.gap);                     % do not join across recording gaps
    if ~isempty(jumps)
        positions = (1:numel(x))' + [0; cumsum(ismember((1:numel(x)-1)', jumps))];
        xx = nan(numel(x) + numel(jumps), 1);
        yy = xx;
        xx(positions) = x;
        yy(positions) = y;
        x = xx;
        y = yy;
    end
    set(h, 'XData', x, 'YData', y);
end
end
