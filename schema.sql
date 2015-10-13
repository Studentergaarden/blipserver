
-- delete readings and all the other objects that depend on it
-- DROP TABLE IF EXISTS readings CASCADE;
DROP table if exists readings CASCADE;
DROP table if exists readings_hourly CASCADE;

CREATE TABLE readings (
	   id INTEGER NOT NULL,
	   stamp BIGINT NOT NULL,
	   ms INTEGER NOT NULL,
	   PRIMARY KEY (id, stamp)
);

CREATE TABLE readings_hourly (
	   id INTEGER NOT NULL,
	   stamp BIGINT NOT NULL,
       events INTEGER NOT NULL,
       sum_ms INTEGER NOT NULL,
       min_ms INTEGER NOT NULL,
       max_ms INTEGER NOT NULL,
	   PRIMARY KEY (id, stamp)
);

CREATE OR REPLACE FUNCTION do_monthly_aggregate() RETURNS trigger AS
$BODY$
DECLARE
  as_date TIMESTAMP WITH TIME ZONE;
  hour BIGINT;
BEGIN
  as_date := TIMESTAMP WITH TIME ZONE 'epoch' + trunc(NEW.stamp/1000) * INTERVAL '1 second';
  hour := 1000::BIGINT * extract(epoch from date_trunc('hour', as_date));
  INSERT INTO readings_hourly (id, stamp, events, sum_ms, min_ms, max_ms)
  SELECT NEW.id, hour, 0, 0, NEW.ms, NEW.ms
   WHERE NOT EXISTS (SELECT 1 FROM readings_hourly R WHERE R.stamp=hour AND R.id=NEW.id);
  UPDATE readings_hourly
     SET events = events + 1,
         sum_ms = sum_ms + NEW.ms,
         min_ms = LEAST(min_ms, NEW.ms),
         max_ms = GREATEST(max_ms, NEW.ms)
   WHERE stamp = hour AND id = NEW.id;
  RETURN NEW;
END;
$BODY$
LANGUAGE plpgsql VOLATILE
COST 100;

CREATE TRIGGER monthly_aggregate AFTER INSERT
    ON readings
   FOR EACH ROW
EXECUTE PROCEDURE do_monthly_aggregate();

CREATE OR REPLACE VIEW usage_hourly AS
SELECT id, stamp, 3600000.0::DOUBLE PRECISION * events / sum_ms AS wh, min_ms, max_ms, events
  FROM readings_hourly;

