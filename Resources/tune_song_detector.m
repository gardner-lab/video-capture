acceptable_lead_in = 60;

% identify valid times to start recording
valid = flipud(tdt);
valid = conv(valid, ones(acceptable_lead_in, 1));
valid = valid(1:size(tdt, 1));
valid = flipud(valid);
valid = (valid > 0);

% starts of songs
starts = 1 + find(valid(2:end) & ~valid(1:(end-1)));
ends = find(valid(1:(end-1)) & ~valid(2:end));

% thresholds
threshold_tdt = 500;
threshold_ratio = 1.5;
threshold_db = 80;

speed_up = nan(length(starts), 1 );

% for each
for i = 1:length(starts)
	s = starts(i);
	e = ends(i);
	
	time_tdt = find(tdt(s:e) > 500, 1);
	time_ratio = find(ratio(s:e) > threshold_ratio & db(s:e) > threshold_db, 1);
	speed_up(i) = time_tdt - time_ratio;
end

fprintf('False negatives: %d\n', sum(isnan(speed_up)));
fprintf('False positives: %d\n', sum(~valid & ratio > threshold_ratio & db > threshold_db));
fprintf('Average speed up: %.2f (%d to %d)\n', mean(speed_up), min(speed_up), max(speed_up));
