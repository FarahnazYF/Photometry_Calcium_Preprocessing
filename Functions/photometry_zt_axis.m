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
% Tick positions and tick labels are always set together, at round values
% chosen for the visible range (6 h apart for a 49-hour view, 0.1 h apart
% for a 1-hour close-up, ...). They are updated when you zoom or pan, and
% they cannot get out of step when the figure is resized.
%
% Also draws a dashed line at every ZT 0 (labelled with the day number)
% and every ZT 12, and links the zoom of all axes.
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
% Put ticks at round values of the visible range and label them with ZT.
% Positions and labels are set in one call, so they always belong together.
if ~isvalid(ax), return; end
limits = ax.XLim;
step = tick_step(diff(limits));
ticks = (ceil(limits(1)/step - 1e-9):floor(limits(2)/step + 1e-9))*step;
decimals = max(0, ceil(-log10(step) - 1e-9));     % decimals needed to write the step
set(ax, 'XTick', ticks, 'XTickLabel', zt_labels(ticks, decimals));
end

function step = tick_step(span)
% Hours between two ticks for a visible range of span hours.
if span > 240
    step = 24;
elseif span > 96
    step = 12;
elseif span > 24
    step = 6;
elseif span > 12
    step = 3;
elseif span > 4
    step = 1;
else
    % Close-ups: about 8 ticks, at 1, 2 or 5 times a power of ten.
    wanted = span/8;
    magnitude = 10^floor(log10(wanted));
    choices = [1 2 5 10]*magnitude;
    step = choices(find(choices >= wanted, 1));
end
end

function labels = zt_labels(ticks, decimals)
% ZT of every tick as text: 30.25 -> '6.25'. A value that rounds to 24 is
% written as 0, because ZT 24 is ZT 0 of the next day.
values = mod(round(mod(ticks, 24), decimals), 24);
labels = cell(size(values));
for k = 1:numel(values)
    label = sprintf('%.*f', decimals, values(k));
    if decimals > 0
        label = regexprep(label, '\.?0+$', '');   % 6.50 -> 6.5 and 6.00 -> 6
    end
    labels{k} = label;
end
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
% ZT with 4 decimals, rounded DOWN so that it never reads 24: a sample just
% before lights ON shows 23.9999 (with its own day), not 24.
zt = floor(photometry_zt(hours)*1e4 + 1e-5)/1e4;
end

function day = day_value(hours)
[~, day] = photometry_zt(hours);
end
