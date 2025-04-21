; -- задача 1

WITH 
-- First, create buffers around street lights in good condition
light_buffers AS (
    SELECT 
        id, 
        ST_Buffer(geom, 10) AS buffer_geom
    FROM 
        ul_osvetlenie
    WHERE 
        condition IN ('добро', 'good', 'отлично', 'excellent')
),

-- Combine all light buffers into a single geometry per district
combined_light_buffers AS (
    SELECT 
        ST_Union(buffer_geom) AS combined_buffer
    FROM 
        light_buffers
),

-- Join roads with districts using spatial relationship (centroid of road in district)
roads_with_districts AS (
    SELECT 
        r.id AS road_id,
        r.geom AS road_geom,
        r.road_categ,
        r.road_name,
        a.id AS district_id,
        a.obns_cyr AS district_name,
        ST_Length(r.geom) AS total_length_m
    FROM 
        municipality_roads_api r
    JOIN 
        adm_rayoni a ON ST_Intersects(ST_Centroid(r.geom), a.geom)
),

-- Calculate the illuminated portions of each road
illuminated_roads AS (
    SELECT 
        r.road_id,
        r.district_id,
        r.district_name,
        r.road_categ,
        r.road_name,
        r.total_length_m,
        r.road_geom,
        COALESCE(ST_Length(ST_Intersection(r.road_geom, c.combined_buffer)), 0) AS illuminated_length_m
    FROM 
        roads_with_districts r
    CROSS JOIN 
        combined_light_buffers c
)

-- Final results with calculations
SELECT 
    road_id,
    district_name,
    road_categ,
    road_name,
    total_length_m / 1000 AS total_length_km,
    illuminated_length_m / 1000 AS illuminated_length_km,
    CASE 
        WHEN total_length_m = 0 THEN 0
        ELSE (illuminated_length_m / total_length_m) * 100 
    END AS illumination_percentage,
    CASE 
        WHEN (illuminated_length_m / total_length_m) * 100 < 30 THEN 'лоша'
        WHEN (illuminated_length_m / total_length_m) * 100 < 70 THEN 'средна'
        ELSE 'добра'
    END AS illumination_quality,
    road_geom
FROM 
    illuminated_roads
ORDER BY 
    district_name, 
    road_categ,
    illumination_percentage DESC;

-- задача 2

WITH school_buffers AS (
  SELECT s.id AS school_id, s.object_nam AS school_name,
         ST_Buffer(s.geom, 1000) AS buffer_geom
  FROM POI_SCHOOLS s
)
SELECT s.school_id, s.school_name,
       COUNT(DISTINCT sp.id) AS sports_facilities_within_1km,
       STRING_AGG(DISTINCT sp.type, ', ') AS facility_types
FROM school_buffers s
LEFT JOIN SPORTNI_PLOSHTADKI sp ON ST_Intersects(s.buffer_geom, sp.geom)
GROUP BY s.school_id, s.school_name
ORDER BY sports_facilities_within_1km DESC;


