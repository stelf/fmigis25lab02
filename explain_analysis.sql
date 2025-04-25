-- Execution Plan Analysis for Current Implementation

-- The current plan shows these key bottlenecks from the latest EXPLAIN output:
-- 1. Nested Loop in lamp_buffer_union CTE (cost=0.28..600947.22, actual time=0.321..1353.614)
-- 2. Large Sort operation (Sort Method: quicksort Memory: 121477kB)
-- 3. Multiple ST_Intersects operations repeated 89,914 times

-- Problem 1: Sequential scan on adm_rayoni
-- Although not a major performance hit (24 rows, 4 buffer hits), the optimizer is choosing a seq scan
-- Solution: Keep the GiST index but consider forcing index usage with SET enable_seqscan=off

-- Problem 2: Inefficient filtering of street lights
-- 6,836 rows are removed by filter after the index scan (8913 shared buffer hits)
-- Solution: Create a partial index specifically for lights with good condition:
-- CREATE INDEX idx_ul_osvetlenie_good_cond ON ul_osvetlenie USING GIST(geom) 
-- WHERE condition IN('много добро', 'отлично', 'добро');

-- Problem 3: Large Sort operations with high memory usage
-- Two major sorts: one using 121477kB and another using 7395kB
-- Solution: Increase work_mem to avoid potential disk spills
-- SET work_mem = '256MB';  -- Based on the 121MB sort requirement

-- Problem 4: Inefficient structure with Nested Loop + Merge Join + GroupAggregate
-- The query plan shows a complex series of operations that could be simplified
-- Solution: Restructure query to union buffers by district before joining with roads

-- Buffer statistics from the execution plan:
-- Total shared buffer hits: 507680
-- Buffer hits in lamp_buffer_union: 9026
-- Buffer hits in road processing: 423438
-- These indicate high I/O activity which could be reduced with better indexing and query structure

-- Memory tuning recommendations based on the explain output:
-- Current Sort operation uses: 121477kB (approximately 119MB)
-- Optimal work_mem setting: at least 150MB to avoid potential spills
-- SET work_mem = '256MB';  -- Conservative recommendation for this workload
-- SET maintenance_work_mem = '512MB'; -- Helpful for vacuum and index operations

-- Performance impact of current approach:
-- Total execution time: 9013.157 ms (about 9 seconds)
-- Main bottlenecks in order of importance:
-- 1. Processing 89,914 buffer geometries individually (1353.614 ms)
-- 2. Large Sort operation (Memory: 121477kB)
-- 3. Complex join structure with multiple sorting steps (4659.896 ms for Incremental Sort)

-- Specific optimization techniques that would help:
-- 1. Union buffers by district to reduce number of geometries from 89,914 to just 24
-- 2. Use hash joins instead of merge joins where appropriate (SET enable_mergejoin=off;)
-- 3. Add a partial index for the specific light condition filter
-- 4. Consider parallelizing the query with SET max_parallel_workers_per_gather = 4;

-- Additional spatial optimization suggestions:
-- 1. Reduce buffer segments: ST_Buffer(geom, 30, 'quad_segs=2') for better performance
-- 2. Pre-compute and cache buffer geometries for frequently queried data
-- 3. Consider using && operator alone for first-pass filtering where possible
-- 4. Use ST_Simplify on complex geometries: ST_Simplify(geom, 0.1) to reduce complexity
