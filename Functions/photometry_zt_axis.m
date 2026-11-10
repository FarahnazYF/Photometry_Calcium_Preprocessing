function photometry_zt_axis(axes_list, range)
%PHOTOMETRY_ZT_AXIS Label a time axis in Zeitgeber time that restarts at every lights ON.
%
%   photometry_zt_axis(axes_list, range)
%
% Inputs
%   axes_list  one or more axes whose x values are hours from the first
%              lights ON (they keep increasing over several days, so the
%              traces are drawn in order)
%   range      [first last] x value to show
%
% The tick labels show Zeitgeber time instead (photometry_zt): 0 to 24,
% restarting at 0 at every lights ON. For example the x value 36 is
% labelled 12, because 36 hours after the first lights ON is ZT 12 of day 2.
%
% Also draws a dashed line at every ZT 0 (labelled with the day number)
% and every ZT 12, links the zoom of all axes, and keeps the labels
% correct when you zoom or pan.
%
% Data tips: when you click (or hover over) a trace, MATLAB would show its
% raw x value, i.e. hours from the first lights ON (e.g. 30.25). The data
% tips of every trace already drawn in these axes are changed to show
% "ZT (h)" (e.g. 6.25) and "Day" (e.g. 2) instead. Call this function after
% plotting.

if range(2) <= range(1), range(2) = range(1) + 1/3600; end   % at least 1 s wide
for ax = axes_list(:)'
    grid(ax, 'on');
    zt_data_tips(ax);
    for mark = 12*ceil(range(1)/12):12:range(2)
        [zt, day] = photometry_zt(mark);
        if zt == 0
            label = sprintf('ZT 0 (day %d)', day);
        else
            label = sprintf('ZT %g', zt);
        end
        xline(ax, mark, '--', label, 'Color', [0.5 0.5 0.5], ...
            'HandleVisibility', 'off', 'LabelVerticalAlignment', 'bottom');
    end
    xlim(ax, range);
    update_ticks(ax);
    addlistener(ax, 'XLim', 'PostSet', @(~, ~) update_ticks(ax));   % zoom and pan
end
if numel(axes_list) > 1, linkaxes(axes_list, 'x'); end
xlabel(axes_list(end), 'Zeitgeber time (ZT, hours; restarts at 0 at every lights ON)');
end

% ==========================================================================
function update_ticks(ax)
% Ticks at round hours, labelled with ZT (0 to 24).
if ~isvalid(ax), return; end
limits = ax.XLim;
span = diff(limits);
if span > 24
    step = 6;
elseif span > 12
    step = 3;
elseif span > 4
    step = 1;
else
    step = [];                       % close-up: let MATLAB choose the ticks
end
if isempty(step)
    ax.XTickMode = 'auto';
    ticks = ax.XTick;
else
    ticks = step*ceil(limits(1)/step):step:limits(2);
    ax.XTick = ticks;
end
ax.XTickLabel = compose('%g', mod(round(photometry_zt(ticks), 4), 24));
end

function zt_data_tips(ax)
% Data tips of every trace: ZT (h) and Day instead of the raw x value.
% The traces are hidden from the legend, so findall (not findobj) is used.
for line = findall(ax, 'Type', 'line')'
    rows = line.DataTipTemplate.DataTipRows;      % default: X, then Y
    line.DataTipTemplate.DataTipRows = [ ...
        dataTipTextRow('ZT (h)', @zt_value); ...
        dataTipTextRow('Day', @day_value); ...
        rows(2:end)];
end
end

function zt = zt_value(hours)
zt = round(photometry_zt(hours), 4);
end

function day = day_value(hours)
[~, day] = photometry_zt(hours);
end
