-- Index suggestions for PostgreSQL 16/17 with PostGIS 3.x:
-- 1. Create a B-tree index on the condition column for faster filtering:
CREATE INDEX IF NOT EXISTS idx_ul_osvetlenie_condition ON ul_osvetlenie (condition);

-- 2. Use GiST index for vector data as SP-GiST doesn't support CLUSTER:
DROP INDEX IF EXISTS spidx_ul_osvetlenie_geom;

CREATE INDEX IF NOT EXISTS idx_ul_osvetlenie_geom ON ul_osvetlenie USING GIST (geom)
WITH
    (fillfactor = 90);

-- 3. Create GiST index for adm_rayoni:
DROP INDEX IF EXISTS brin_adm_rayoni_geom;

DROP INDEX IF EXISTS spidx_adm_rayoni_geom;

CREATE INDEX IF NOT EXISTS idx_adm_rayoni_geom ON adm_rayoni USING GIST (geom)
WITH
    (fillfactor = 90);

-- 4. For road network, GiST still performs well but with tuned parameters:
DROP INDEX IF EXISTS spidx_osi_ulici_26_osm_geom;

CREATE INDEX IF NOT EXISTS idx_osi_ulici_26_osm_geom ON osi_ulici_26_osm USING GIST (geom)
WITH
    (fillfactor = 90);

-- 5. CLUSTER tables to physically organize by spatial index:
-- Note: CLUSTER requires a B-tree or GiST index (not SP-GiST)
CLUSTER ul_osvetlenie USING idx_ul_osvetlenie_geom;

CLUSTER osi_ulici_26_osm USING idx_osi_ulici_26_osm_geom;

-- 6. Update statistics for the query planner:
VACUUM ANALYZE ul_osvetlenie;
VACUUM ANALYZE adm_rayoni;
VACUUM ANALYZE osi_ulici_26_osm;

explain (analyze, buffers)
WITH
    -- Стъпка 1: Създаване на геометрия представяща (областта на осветеност) на дадена лампа
    lamp_buffer_union AS materialized (
        SELECT
            adm_rayoni.obns_cyr as district,
            ST_Buffer (ul_osvetlenie.geom, 30, 4) AS geom
        FROM
            ul_osvetlenie,
            adm_rayoni
        WHERE
            ST_CONTAINS (adm_rayoni.geom, ul_osvetlenie.geom)
            and condition in ('много добро', 'отлично', 'добро')
    ),
    -- Стъпка 2: Пресичане на пътищата с буфера (намиране на осветените участъци и дължини)
    -- Пресмята: осветените части от улиците, определител на улицата и дължина на осв. част
    -- Обърнете внимание, че не сумираме тук дължините на улиците, защото една улица е 
    -- вероятно да присъства повече от веднъж в резултата, тъй като тук имаме брой пресичания
    -- колкото са лампите (и съответно толкова отсечки), а не колкото са уилиците 
    road_lit_parts_lens AS (
        SELECT
            u.district,
            r.id,
            st_length (ST_Intersection (r.geom, u.geom)) AS lit_m
        FROM
            osi_ulici_26_osm r,
            lamp_buffer_union u
        WHERE
            ST_Intersects (r.geom, u.geom)
    ),
    -- Стъпка 3: Натрупване дължина на осв.части (по улица), запазвайки район в резултата
    -- Възможно е да се направи още на предната стъпка, но го прави за яснота по този начин
    lit_grouped AS materialized (
        SELECT
            rlp.district,
            st_length (ou.geom) as total_len_m,
            SUM(rlp.lit_m) AS lit_m
        FROM
            road_lit_parts_lens rlp
            inner join osi_ulici_26_osm ou using (id)
        GROUP BY
            ou.id,
            rlp.district
    )
    -- Стъпка 4: групиране по квартал и сумиране дължините на самите улици, които вече имаме
    -- само веднъж в предишния резултат, а не множество пъти. 
    select
        district,
        sum(lit_m) as total_lit_m,
        sum(total_len_m) as total_len_m
    from
        lit_grouped lg
    group by
        district;