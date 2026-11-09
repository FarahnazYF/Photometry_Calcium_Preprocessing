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

if range(2) <= range(1), range(2) = range(1) + 1/3600; end   % at least 1 s wide
for ax = axes_list(:)'
    grid(ax, 'on');
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
