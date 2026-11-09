function photometry_plot_qc(step, data, cfg)
%PHOTOMETRY_PLOT_QC Quality-control figures, one per processing step.
%
%   photometry_plot_qc(step, data, cfg)
%
%   step          figure
%   'extracted'   Figure 1  extracted 405 and 470 over the whole recording
%   'sawtooth'    Figure 2  405 before/after sawtooth removal (close-up) and
%                           what was removed
%   'lowpass'     Figure 3  30-s close-up of both channels before/after the
%                           low-pass filter
%   'bleaching'   Figure 4  filtered channels with the fitted bleaching
%                           trends, and the corrected channels
%   'artifacts'   Figure 5  preliminary motion-corrected 470 with the
%                           automatic artifact suggestions
%   'motion'      Figure 6  405 against 470 with the IRLS line, and the
%                           fitted 405 over the 470
%   'final'       Figure 7  dF/F without and with the rolling median (zoom in
%                           to see every sample)
%
% Shown if cfg.show_figures is true; saved as PNG files in the results
% folder ("figures") if cfg.save_figures is true. Long traces are drawn
% with at most about cfg.max_plot_points points (display only).
% The x axis is labelled in Zeitgeber time (ZT 0 = lights ON), restarting
% at 0 at every lights ON (photometry_zt_axis).

if ~cfg.show_figures && ~cfg.save_figures, return; end
h0 = data.crop_info.start_hours_from_lights_on;   % time zero in hours from the first lights ON
hours = h0 + data.time_s(:)/3600;                 % every sample, in hours from the first lights ON
hours_range = [min(hours) max(hours)];
blue = [0 0.35 0.9]; green = [0 0.6 0]; grey = [0.6 0.6 0.6];

switch step
    case 'extracted'
        f = new_figure('Figure 1 - Extracted 405 and 470 signals', cfg);
        tl = tiledlayout(f, 2, 1, 'TileSpacing', 'compact');
        ax1 = nexttile(tl); hold(ax1, 'on');
        photometry_plot_trace(ax1, hours, data.raw405, cfg.max_plot_points, 'Color', blue);
        ylabel(ax1, '405 (PMT units)'); title(ax1, '405 nm (isosbestic control)');
        ax2 = nexttile(tl); hold(ax2, 'on');
        photometry_plot_trace(ax2, h0 + data.time470_s(:)/3600, data.raw470, cfg.max_plot_points, 'Color', green);
        ylabel(ax2, '470 (PMT units)'); title(ax2, '470 nm (calcium signal)');
        photometry_zt_axis([ax1 ax2], hours_range);
        sgtitle(f, sprintf('One value per LED pulse | %g pulses per second | analysis starts at %s (%g h before lights ON)', ...
            cfg.sample_rate_hz, data.crop_info.reference_clock, -h0));
        finish(f, cfg);

    case 'sawtooth'
        if ~data.sawtooth_removed || data.sawtooth_info.windows_applied == 0
            return;                            % nothing was removed: nothing to show
        end
        f = new_figure('Figure 2 - Sawtooth removal from 405', cfg);
        tl = tiledlayout(f, 2, 1, 'TileSpacing', 'compact');
        % Close-up: 3 minutes from the middle of the first window that was changed.
        w = data.sawtooth_info.windows(find(data.sawtooth_info.windows.applied, 1), :);
        centre = round((w.first_index + w.last_index)/2);
        half = round(90*cfg.sample_rate_hz);
        idx = max(1, centre-half):min(numel(hours), centre+half);
        before = data.raw405(:); before(data.trim_mask) = NaN;
        [~, ~, start_label] = photometry_zt(hours(idx(1)));
        ax1 = nexttile(tl); hold(ax1, 'on');
        plot(ax1, (data.time_s(idx) - data.time_s(idx(1))), before(idx), 'Color', grey, 'DisplayName', 'before');
        plot(ax1, (data.time_s(idx) - data.time_s(idx(1))), data.cleaned405(idx), 'Color', blue, 'DisplayName', 'after');
        xlabel(ax1, sprintf('Seconds (from %s)', start_label)); ylabel(ax1, '405 (PMT units)');
        title(ax1, sprintf('Close-up: 405 before and after (period here %.2f s)', w.period_s));
        legend(ax1, 'Location', 'best'); grid(ax1, 'on');
        ax2 = nexttile(tl); hold(ax2, 'on');
        series(ax2, hours, data.sawtooth_estimate, data.phase_windows, cfg, 'Color', [0.85 0.2 0.1]);
        ylabel(ax2, 'Removed (PMT units)');
        title(ax2, sprintf('What was removed, whole recording (changed in %d of %d windows)', ...
            data.sawtooth_info.windows_applied, data.sawtooth_info.windows_total));
        photometry_zt_axis(ax2, hours_range);
        finish(f, cfg);

    case 'lowpass'
        f = new_figure('Figure 3 - Low-pass filter (close-up)', cfg);
        tl = tiledlayout(f, 2, 1, 'TileSpacing', 'compact');
        % 30 seconds from the middle of the first phase, every sample.
        a = data.phase_windows(1, 1); b = data.phase_windows(1, 2);
        centre = round((a + b)/2);
        half = round(15*cfg.sample_rate_hz);
        idx = max(a, centre-half):min(b, centre+half);
        seconds = data.time_s(idx) - data.time_s(idx(1));
        inputs = {data.cleaned405, data.trimmed470};
        outputs = {data.filtered405, data.filtered470};
        names = {'405', '470'}; colours = {blue, green};
        for k = 1:2
            ax = nexttile(tl); hold(ax, 'on');
            plot(ax, seconds, inputs{k}(idx), 'Color', grey, 'DisplayName', 'before');
            plot(ax, seconds, outputs{k}(idx), 'Color', colours{k}, 'LineWidth', 1.2, 'DisplayName', 'after');
            ylabel(ax, [names{k} ' (PMT units)']); legend(ax, 'Location', 'best'); grid(ax, 'on');
            title(ax, sprintf('%s, 30 s from the middle of phase 1', names{k}));
        end
        [~, ~, start_label] = photometry_zt(hours(idx(1)));
        xlabel(ax, sprintf('Seconds (from %s)', start_label));
        if strcmp(data.lowpass_info.method, 'butterworth')
            text_method = sprintf('Butterworth, order %d, %g Hz, forwards and backwards', ...
                data.lowpass_info.order, data.lowpass_info.cutoff_hz);
        else
            text_method = sprintf('rolling mean, %g s', data.lowpass_info.window_sec);
        end
        sgtitle(f, ['Low-pass filter: ' text_method]);
        finish(f, cfg);

    case 'bleaching'
        f = new_figure('Figure 4 - Photobleaching correction', cfg);
        tl = tiledlayout(f, 3, 1, 'TileSpacing', 'compact');
        ax1 = nexttile(tl); hold(ax1, 'on');
        series(ax1, hours, data.filtered405, data.phase_windows, cfg, 'Color', blue, 'DisplayName', 'filtered 405');
        series(ax1, hours, data.bleaching_trend405, data.phase_windows, cfg, 'Color', 'k', 'LineWidth', 1.5, ...
            'DisplayName', 'fitted trend');
        ylabel(ax1, '405 (PMT units)'); legend(ax1, 'Location', 'best');
        ax2 = nexttile(tl); hold(ax2, 'on');
        series(ax2, hours, data.filtered470, data.phase_windows, cfg, 'Color', green, 'DisplayName', 'filtered 470');
        series(ax2, hours, data.bleaching_trend470, data.phase_windows, cfg, 'Color', 'k', 'LineWidth', 1.5, ...
            'DisplayName', 'fitted trend');
        ylabel(ax2, '470 (PMT units)'); legend(ax2, 'Location', 'best');
        ax3 = nexttile(tl); hold(ax3, 'on');
        series(ax3, hours, data.corrected405, data.phase_windows, cfg, 'Color', blue, 'DisplayName', '405');
        series(ax3, hours, data.corrected470, data.phase_windows, cfg, 'Color', green, 'DisplayName', '470');
        yline(ax3, 1, 'k:', 'HandleVisibility', 'off');
        ylabel(ax3, 'signal / trend'); legend(ax3, 'Location', 'best');
        title(ax3, 'After the correction (both channels around 1)');
        photometry_zt_axis([ax1 ax2 ax3], hours_range);
        sgtitle(f, 'Photobleaching: a double exponential is fitted in each phase and divided out');
        finish(f, cfg);

    case 'artifacts'
        f = new_figure('Figure 5 - Automatic artifact suggestions', cfg);
        tl = tiledlayout(f, 2, 1, 'TileSpacing', 'compact');
        ax1 = nexttile(tl); hold(ax1, 'on');
        series(ax1, hours, data.preliminary_residual, data.phase_windows, cfg, 'Color', green, ...
            'DisplayName', '470 - fitted 405 (preliminary)');
        events = data.artifact_suggestions;
        if ~isempty(events)
            [~, peak] = ismember(events.peak_s, data.time_s);   % sample number of each peak
            plot(ax1, hours(peak), data.preliminary_residual(peak), 'ro', 'MarkerSize', 6, ...
                'DisplayName', 'suggested artifact');
        end
        ylabel(ax1, 'Motion-corrected 470'); legend(ax1, 'Location', 'best');
        title(ax1, sprintf('%d suggested artifacts (nothing removed automatically)', height(events)));
        ax2 = nexttile(tl); hold(ax2, 'on');
        series(ax2, hours, data.corrected405, data.phase_windows, cfg, 'Color', blue);
        ylabel(ax2, '405, bleaching-corrected');
        photometry_zt_axis([ax1 ax2], hours_range);
        finish(f, cfg);

    case 'motion'
        f = new_figure('Figure 6 - Motion correction (IRLS)', cfg);
        tl = tiledlayout(f, 2, 1, 'TileSpacing', 'compact');
        ax1 = nexttile(tl); hold(ax1, 'on');
        used = find(data.valid_mask);
        shown = used(round(linspace(1, numel(used), min(numel(used), cfg.max_plot_points))));
        plot(ax1, data.corrected405(shown), data.corrected470(shown), '.', 'Color', [0.4 0.4 0.4], ...
            'MarkerSize', 3, 'DisplayName', sprintf('samples (%d of %d shown)', numel(shown), numel(used)));
        limits = [min(data.corrected405(shown)) max(data.corrected405(shown))];
        plot(ax1, limits, polyval([data.motion_fit.slope data.motion_fit.intercept], limits), 'r-', ...
            'LineWidth', 2, 'DisplayName', sprintf('IRLS line: %.3g x 405 + %.3g', ...
            data.motion_fit.slope, data.motion_fit.intercept));
        xlabel(ax1, '405, bleaching-corrected'); ylabel(ax1, '470, bleaching-corrected');
        legend(ax1, 'Location', 'best'); grid(ax1, 'on');
        title(ax1, sprintf('405 against 470 (c = %g; %.1f%% of samples got weight 0)', ...
            data.motion_fit.tuning_constant, data.motion_fit.zero_weight_percent));
        ax2 = nexttile(tl); hold(ax2, 'on');
        fitted = data.fitted405; fitted(~data.valid_mask) = NaN;
        signal = data.corrected470; signal(~data.valid_mask) = NaN;
        series(ax2, hours, signal, data.phase_windows, cfg, 'Color', green, 'DisplayName', '470');
        series(ax2, hours, fitted, data.phase_windows, cfg, 'Color', [0.75 0 0.75], 'DisplayName', 'fitted 405');
        ylabel(ax2, 'bleaching-corrected'); legend(ax2, 'Location', 'best');
        title(ax2, 'dF/F = (470 - fitted 405) / fitted 405');
        photometry_zt_axis(ax2, hours_range);
        finish(f, cfg);

    case 'final'
        f = new_figure('Figure 7 - Final dF-F', cfg);
        tl = tiledlayout(f, 2, 1, 'TileSpacing', 'compact');
        versions = {data.dF_F, data.dF_F_rolling_median};
        infos = {data.z_info, data.z_info_rolling_median};
        names = {'dF/F without rolling median', ...
            sprintf('dF/F after subtracting a %g-s rolling median', cfg.rolling_median_window_sec)};
        colours = {[0 0 0], blue};
        ax = gobjects(2, 1);
        for k = 1:2
            ax(k) = nexttile(tl); hold(ax(k), 'on');
            for p = 1:size(data.phase_windows, 1)      % one line per phase: phases are not joined
                idx = data.phase_windows(p, 1):data.phase_windows(p, 2);
                photometry_plot_zoomable(ax(k), hours(idx), 100*versions{k}(idx), cfg.max_plot_points, ...
                    'Color', colours{k});
            end
            yline(ax(k), 0, ':', 'HandleVisibility', 'off');
            ylabel(ax(k), 'dF/F (%)');
            title(ax(k), sprintf('%s | z: mean %.3g%%, SD %.3g%% | robust z: median %.3g%%, 1.4826 x MAD %.3g%%', ...
                names{k}, 100*infos{k}.mean, 100*infos{k}.std, 100*infos{k}.median, 100*infos{k}.robust_sd));
        end
        photometry_zt_axis(ax, hours_range);
        sgtitle(f, sprintf(['Final dF/F (z-scores are these traces rescaled; see titles). ' ...
            'Zoom in to under %.1f minutes to see every sample.'], cfg.max_plot_points/cfg.sample_rate_hz/60));
        finish(f, cfg);

    otherwise
        error('photometry:Figure', 'Unknown figure step: %s', step);
end
end

% ==========================================================================
function series(ax, x, y, phase_windows, cfg, varargin)
% Draw each phase as its own line, so separate phases are not joined.
% If a 'DisplayName' is given, one empty, thicker line with the same colour
% is added for the legend (legend samples of the thin, dense traces are
% hard to see).
for p = 1:size(phase_windows, 1)
    idx = phase_windows(p, 1):phase_windows(p, 2);
    photometry_plot_trace(ax, x(idx), y(idx), cfg.max_plot_points, varargin{:}, ...
        'HandleVisibility', 'off');
end
if any(strcmpi(varargin(1:2:end), 'DisplayName'))
    plot(ax, NaN, NaN, varargin{:}, 'LineWidth', 2);
end
end

function f = new_figure(name, cfg)
visibility = 'off'; if cfg.show_figures, visibility = 'on'; end
f = figure('Name', name, 'NumberTitle', 'off', 'Color', 'w', 'Visible', visibility, ...
    'Position', [60 60 1300 850]);
end

function finish(f, cfg)
drawnow;
if cfg.save_figures
    files = photometry_output_files(cfg);
    folder = files.figures_folder;
    if ~isfolder(folder), mkdir(folder); end
    name = regexprep(regexprep(f.Name, '[^A-Za-z0-9]+', '_'), '^_|_$', '');   % e.g. Figure_7_Final_dF_F
    exportgraphics(f, fullfile(folder, [name '.png']), 'Resolution', 150);
end
if ~cfg.show_figures, close(f); end
end
