function line_handle = photometry_plot_trace(ax, time, signal, max_points, varargin)
%PHOTOMETRY_PLOT_TRACE Plot a long trace quickly without hiding short peaks.
%
%   h = photometry_plot_trace(ax, time, signal, max_points, ...plot options...)
%
% A 49-hour recording at 50 Hz has almost 9 million samples; drawing all
% of them makes figures slow. If the trace has more than max_points
% samples, it is cut into short blocks and only the lowest and highest
% value of each block are drawn. At the scale of the whole trace this
% looks the same as drawing every sample, and short peaks are not lost.
% (This is for display only; the analysis always uses every sample.)
%
% Recording gaps (pauses longer than 1.5 x the usual sample interval) are
% drawn as breaks, so separate stretches are not joined by a straight line.
%
% Inputs
%   ax          the axes to draw in
%   time        x values, one per sample (or a scalar = seconds per sample)
%   signal      y values
%   max_points  about how many points to draw
%   ...         any plot options, e.g. 'Color', 'b', 'DisplayName', '405'

y = signal(:);
n = numel(y);
if n == 0
    line_handle = plot(ax, NaN, NaN, varargin{:});
    return;
end

% ---- Which samples to draw -----------------------------------------------
if n <= max_points
    selected = (1:n)';
else
    n_blocks = max(1, floor(max_points/4));
    edges = floor(linspace(1, n+1, n_blocks+1));
    pieces = cell(n_blocks, 1);
    for k = 1:n_blocks
        a = edges(k); b = edges(k+1) - 1;
        block = y(a:b);
        [~, imin] = min(block, [], 'omitnan');
        [~, imax] = max(block, [], 'omitnan');
        % Keep the edges of missing stretches, so gaps are not filled in.
        missing = ~isfinite(block);
        boundaries = find(diff(missing) ~= 0);
        pieces{k} = unique([a; b; a+imin-1; a+imax-1; a+boundaries-1; a+boundaries]);
    end
    selected = unique(vertcat(pieces{:}));
end

% ---- Find recording gaps ---------------------------------------------------
gap_before = [];
if ~isscalar(time) && numel(time) > 1
    intervals = diff(time(1:min(n, 10000)));
    interval = median(intervals(intervals > 0));
    if ~isempty(interval) && isfinite(interval)
        gap_before = find(diff(time(:)) > 1.5*interval);
        selected = unique([selected; gap_before; gap_before+1]);
    end
end

% ---- x values ----------------------------------------------------------------
if isscalar(time)
    x = (selected - 1)*time;
else
    if numel(time) ~= n, error('photometry:Plot', 'time and signal must have the same length.'); end
    x = time(selected);
end
x = x(:);
values = y(selected);

% ---- Insert a NaN at every gap, so the line breaks there -------------------
if ~isempty(gap_before)
    after = ismember(selected, gap_before);
    positions = (1:numel(selected))' + [0; cumsum(after(1:end-1))];
    expanded_x = nan(numel(selected) + nnz(after), 1);
    expanded_y = expanded_x;
    expanded_x(positions) = x;
    expanded_y(positions) = values;
    x = expanded_x;
    values = expanded_y;
end
line_handle = plot(ax, x, values, varargin{:});
end
