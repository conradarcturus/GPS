function gpsp_draw_grangerpackets(state)
% Creates an animation of granger activity across the cortex.
%
% Author: Conrad Nied
%
% Input: 
% Output: 
%
% Changelog:
% 2013.02.12 - Created in GPS1.7/gpsp_draw_grangerpackets
% 2013.02.13 - Changed lines from straight to curved by on dijkstra and
% weighting.

%% Parameters

study = gpsa_parameter(state, state.study);
subset = gpsa_parameter(state, state.subset);
state.function = 'gpsp_draw_grangerpackets';
tbegin = tic;

if(~study.granger.singlesubject)
    state.subject = study.average_name;
end

% imdir = sprintf('%s/images/%s', state.dir, datestr(now, 'yymmdd'));
imdir = sprintf('%s/images/dev/grngmov_curved', state.dir);
if(~exist(imdir, 'dir'))
    mkdir(imdir);
end

%% Load Data

% Load brain data
brain = gps_brain_get(state);

% Load ROI data
points = sprintf('%s/rois/%s/%s/%s_rois.mat', study.granger.dir, subset.cortex.roiset, state.subject, state.subject);
points = load(points);
points = points.rois;

% Get interactions data
inputfilename = gpsa_granger_filename(state, 'result');
folder = inputfilename(1:find(inputfilename == '/', 1, 'last'));
outputfilename = sprintf('%s_significance*.mat', inputfilename(1:end-4));
outputfilename = dir(outputfilename);
outputfilename = [folder outputfilename(end).name];
grangerfile = load(outputfilename);

N_comp = 2000;
results = grangerfile.granger_results;

srcs = grangerfile.src_ROIs;
if(isfield(grangerfile, 'sink_ROIs')); grangerfile.snk_ROIs = grangerfile.sink_ROIs; end
snks = grangerfile.snk_ROIs;

p_values = zeros(size(results));
p_values = squeeze(mean(...
    repmat(results(srcs, snks, :), [1 1 1 N_comp])...
    >= grangerfile.total_control_granger, 4));
p_values(srcs, snks, :) = p_values;

perc95 = zeros(size(results));
perc95_focused = quantile(grangerfile.total_control_granger, 0.95, 4);
perc95(srcs, snks, :) = perc95_focused;

[N_rois, ~, N_time] = size(results);

clear grangerfile

%% Create Template brain background

% Draw generic brain with & save image

W = 600;
H = 450;
A = W*H;
figure(1)
clf
set(gcf, 'Units', 'Pixels');
set(gcf, 'Position', [10, 10, W, H]);
set(gca, 'Units', 'Pixels');
set(gca, 'Position', [10, 10, W-20, H-20]);

options.shading = 1;
options.curvature = 'bin';
options.sides = {'ll', 'rl', 'lm', 'rm'};
options.fig = gcf;
options.axes = gca;
options.centroids = 0;

gps_brain_draw(brain, options);

% Save image of generic brain
frame = getframe(gcf);
brain_image = frame.cdata;
filename = sprintf('%s/cortex.png', folder);
imwrite(brain_image, filename, 'png');

% Draw ROIs on the the brain for triangulation
brain.points = points;
options.centroids = 1;
options.centroids_color = zeros(N_rois, 3);
options.centroids_color(:, 1) = (1:N_rois)/N_rois;
options.centroids_circles = false;
options.centroids_radius = 1;

gps_brain_draw(brain, options);

% Recover pixel locations for each ROI on the brain image
frame = getframe(gcf);
brain_image_rois = frame.cdata;
red = brain_image_rois(:, :, 1);
rois_pxloc = find(red ~= brain_image_rois(:, :, 2));
rois_pxloc(round(double(red(rois_pxloc))/255 * N_rois)) = rois_pxloc;
i2xy = @(i) [floor((i - 1) / H) + 1 mod((i - 1), H) + 1];
% rois_pxloc_xy = [floor((rois_pxloc-1) / H) + 1 mod((rois_pxloc-1), H) + 1];
rois_pxloc_xy =i2xy(rois_pxloc-1);


%% Draw Packet overlays

% Determine lines
figure(2)
clf
set(gcf, 'Units', 'Pixels');
set(gcf, 'Position', [10, 10, W+10, H+10]);
set(gca, 'Units', 'Pixels');
set(gca, 'Position', [5, 5, W, H]);
image(brain_image)
axis off;
hold on;
cols = hsv(N_rois);

% Create adjacency and distance matrices
adjacent = zeros(A, 9);
adjacent(:, 5) = 1:A; % Center
adjacent(:, 4) = adjacent(:, 5) - 1; % Top
adjacent(1:H:A, 4) = (1:H:A) - A/2; % Correct Top Top
adjacent(:, 6) = adjacent(:, 5) + 1; % Bottom
adjacent(H:H:A, 6) = (H:H:A) - W*H/2; % Correct Bottom Bottom
adjacent(:, 1) = adjacent(:, 4) - H;
adjacent(:, 2) = adjacent(:, 5) - H;
adjacent(:, 3) = adjacent(:, 6) - H;
adjacent(:, 7) = adjacent(:, 4) + H;
adjacent(:, 8) = adjacent(:, 5) + H;
adjacent(:, 9) = adjacent(:, 6) + H;
adjacent = mod(adjacent-1, A)+1; % Correct overflows
adjacent(:, 5) = []; % Remove self-loop;

adjacent_dist = zeros(A, 8);
adjacent_dist(:, [2 4 5 7]) = 1;
adjacent_dist(:, [1 3 6 8]) = power(2, 0.5);
keyboard
lines = cell(N_rois);
fprintf('computing distances\n\t')
for i_roi = 1:N_rois
    fprintf('%d ', i_roi);
    [~, lasthop] = gpsp_dijkstra(rois_pxloc(i_roi), adjacent, adjacent_dist);
    
    for j_roi = 1:N_rois
        index = rois_pxloc(j_roi);
        
        % Trace back the last hop to build the line;
        i_point = 0;
        nexthop = index;
        roiline = [];
        while(nexthop ~= 0)
            i_point = i_point + 1;
            roiline(i_point) = nexthop; %#ok<AGROW>
            nexthop = lasthop(nexthop);
        end
        lines{i_roi, j_roi} = i2xy(roiline);
        
        plot(roiline(:, 1), roiline(:, 2), 'Color', cols(i_roi, :), 'LineStyle', 'none', 'Marker', '+', 'MarkerSize', 1)
    end
    plot(rois_pxloc_xy(i_roi, 1), rois_pxloc_xy(i_roi, 2), 'w+')
end
fprintf('\n\tdone computing distances\n')
keyboard
frame = getframe(gca);
filename = sprintf('%s/cortex_lines.png', imdir);
imwrite(frame.cdata, filename, 'png');

%% Fill the lines with the GCI

N_frames = 20;
trail_length = 10;
times_ms = 200:400;
times_samples = times_ms + 1;
N_time = length(times_samples);

for i_time = 1%:N_time
    for i_frame = 1:N_frames
        %     figure(4)
        %     clf
        %     image(brain_image)
        %     hold on;
        frame_image = brain_image;
        cols = hsv(N_rois);
        
        for i_roi = 1:N_rois
            for j_roi = 1:N_rois
                roiline = lines{i_roi, j_roi};
                value = results(j_roi, i_roi, times_samples(i_time)) -.2;
                
                if(value > 0)
                    for darkstep = 1:trail_length
                        if(value > 2); value = 2; end
                        ratio = round(0.5 / value);
                        offset = mod(i_frame + darkstep - 2, ratio) + 1;
%                         roipoints = roiline(offset:ratio:length(roiline), :);
                        
                        % plot(roipoints(:, 1), roipoints(:, 2), 'Color', cols(i_roi, :) * darkstep / trail_length, 'LineStyle', 'none', 'Marker', '+', 'MarkerSize', 1)
%                             frame_image(roipoints(:, 1), roipoints(:, 2), 1) = cols(i_roi, 1) * darkstep / trail_length * 255;
                        for i_point = offset:ratio:length(roiline)
                            frame_image(roiline(i_point, 2), roiline(i_point, 1), 1) = max(frame_image(roiline(i_point, 2), roiline(i_point, 1), 1) , cols(i_roi, 1) * darkstep / trail_length * 255);
                            frame_image(roiline(i_point, 2), roiline(i_point, 1), 2) = max(frame_image(roiline(i_point, 2), roiline(i_point, 1), 2) , cols(i_roi, 2) * darkstep / trail_length * 255);
                            frame_image(roiline(i_point, 2), roiline(i_point, 1), 3) = max(frame_image(roiline(i_point, 2), roiline(i_point, 1), 3) , cols(i_roi, 3) * darkstep / trail_length * 255);
                        end
                    end
                end % If there is a line to make
            end % For each sink
        end % For each source
        
        % Save image
        filename = sprintf('%s/cortex_t%04d_f%02d.png', imdir, times_ms(i_time), i_frame);
        imwrite(frame_image, filename, 'png');
    end % for each frame
end % for each timepoint

end