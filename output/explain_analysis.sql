-- Execution Plan Analysis

-- The current plan shows these key bottlenecks:
-- 1. Nested Loop causing high execution time (~9.3 seconds)
-- 2. Large number of rows processed (89,914 in CTE lamp_buffer_union)
-- 3. Multiple ST_Intersects and ST_Buffer operations

-- Problem 1: Sequential scan on adm_rayoni
-- This isn't a major issue since there are only 24 rows, but we can still optimize it
-- Solution: Make sure the GiST index on adm_rayoni.geom is being used for spatial queries

-- Problem 2: Inefficient filtering of street lights
-- The index scan on ul_osvetlenie is removing 6,836 rows with the filter condition
-- Solution: Create partial index for lights with good condition to avoid this filter

-- Problem 3: Major bottleneck - Nested Loop with CTE scan
-- The most expensive part is joining 89,914 buffer geometries with roads
-- Solution: Reduce this by unioning buffer geometries by district first

-- Problem 4: Temp Written Blocks
-- 3,746 blocks written to temp files, indicating memory pressure
-- Solution: Increase work_mem to minimize disk spills during operation

-- Work_mem optimization strategy:
-- 1. Determine current work_mem setting: SHOW work_mem;
-- 2. Calculate ideal work_mem based on query needs:
--    - Each nested loop join might use up to work_mem memory
--    - For this query with ~90K geometries, consider 256MB-512MB
-- 3. Set work_mem before running the query:
SET work_mem = '256MB';  -- Adjust based on available system memory
-- 4. For production, consider setting per-session rather than globally:
--    ALTER ROLE your_username SET work_mem = '256MB';
-- 5. Monitor for improvement by checking if temp blocks decrease

-- Work_mem tuning considerations:
-- - Too low: Causes excessive disk spills (temp files)
-- - Too high: Risks server memory pressure with concurrent queries
-- - Optimal: Just enough to keep operations in memory
-- - For spatial operations, higher values often help significantly
-- - Start with 2-4x the current temp blocks size and adjust based on results

-- Specific work_mem recommendations for this query:
-- Small server (4-8GB RAM): SET work_mem = '128MB';
-- Medium server (16-32GB RAM): SET work_mem = '256MB';
-- Large server (64GB+ RAM): SET work_mem = '512MB';

-- To monitor memory usage during query execution:
-- SELECT * FROM pg_stat_activity WHERE state = 'active';

-- Problem 5: ST_Buffer and ST_Intersection operations
-- These are expensive operations executed many times
-- Solution: Reduce their frequency by preprocessing or simplifying geometries

-- Specific optimization techniques:
-- 1. Pre-filter lights by condition before spatial operations
-- 2. Union buffers by district to minimize the number of road intersections
-- 3. Use MATERIALIZED for all CTEs to ensure results are stored once
-- 4. Consider parallel processing by splitting districts into chunks
-- 5. Use transaction-based approach with temporary tables for very large datasets

-- Memory tuning parameters:
-- SET work_mem = '128MB';           -- Increase working memory for sorts and hashes
-- SET maintenance_work_mem = '1GB'; -- For index creation and vacuum
-- SET effective_cache_size = '4GB'; -- Hint for query planner about available cache
-- SET random_page_cost = 1.1;       -- If using SSD storage
-- SET effective_io_concurrency = 200; -- For SSD storage

-- Additional spatial optimization techniques:
-- 1. ST_Simplify geometries for faster processing if precision isn't critical
-- 2. ST_ReducePrecision for complex geometries
-- 3. Consider using KNN distance operators for initial filtering
-- 4. Use ST_Subdivide for very large geometries before processing

-- Problem: Expensive Sort Operation
-- The plan shows a large sort operation consuming 119MB of memory:
--         Sort Key: u.district                                   
--         Sort Method: quicksort  Memory: 119688kB  
-- Solution: Pre-aggregate by district before joining with roads

-- Strategies to avoid the sort operation:
-- 1. Pre-group lamp buffers by district before intersection
--    - This reduces the number of geometries to process by ~24x
--    - The sort becomes unnecessary as we're already working with district-level data
-- 
-- 2. Use a hash aggregate instead of sort aggregate
--    - Add "SET enable_sort = off;" before query to force hash aggregation
--    - Hash aggregation often performs better for this type of grouping
--
-- 3. Modify the query structure to avoid sorting:
--    WITH lamp_buffer_by_district AS (
--       SELECT district, ST_Union(geom) AS geom
--       FROM lamp_buffer_union
--       GROUP BY district
--    )
--    - Then join this smaller dataset with roads

-- Example implementation that avoids sorting:
WITH lamp_buffers AS MATERIALIZED (
    SELECT
        adm_rayoni.obns_cyr as district,
        ST_Buffer(ul_osvetlenie.geom, 30, 'quad_segs=4') AS geom 
    FROM ul_osvetlenie
    JOIN adm_rayoni ON ST_Contains(adm_rayoni.geom, ul_osvetlenie.geom)
    WHERE condition IN('много добро', 'отлично', 'добро')
),
district_buffer_union AS MATERIALIZED (
    -- Pre-aggregate by district to avoid later sorting
    SELECT 
        district, 
        ST_Union(geom) AS geom
    FROM lamp_buffers
    GROUP BY district
),
road_lit_parts AS (
    -- Now we work with only 24 district geometries instead of 89,914 lamp buffers
    SELECT
        d.district,
        r.id,
        ST_Length(r.geom) as total_m,
        ST_Length(ST_Intersection(r.geom, d.geom)) AS lit_m
    FROM osi_ulici_26_osm r
    JOIN district_buffer_union d ON ST_Intersects(r.geom, d.geom)
)
SELECT
    district,
    SUM(total_m) AS total_len_m,
    SUM(lit_m) AS total_lit_m
FROM road_lit_parts
GROUP BY district;

-- Additional tuning parameter to favor hash aggregation over sorting:
SET enable_sort = off;      -- Forces planner to avoid sort operations
SET enable_hashagg = on;    -- Ensures hash aggregation is considered
