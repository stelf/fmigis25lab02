explain analyze verbose 
-- Анализ на осветлението на пътната мрежа
-- Стъпка 1: Създаване и обединяване на примерен буфер около лампите в добро състояние
WITH lamp_buffer_union  AS materialized (
    SELECT
        adm_rayoni.obns_cyr as district,
    	ST_Buffer(ul_osvetlenie.geom, 30, 4) AS geom 
    FROM ul_osvetlenie, adm_rayoni
    WHERE
        ST_CONTAINS(adm_rayoni.geom, ul_osvetlenie.geom) and
        condition in('много добро', 'отлично', 'добро')
),
-- Стъпка 2: Пресичане на пътищата с буфера (намиране на осветените участъци и дължини)
road_lit_parts_lens AS (
    SELECT
        u.district,
        r.id,
        st_length(r.geom) as total_m,
        st_length(ST_Intersection(r.geom, u.geom)) AS lit_m
    FROM osi_ulici_26_osm r,
    	 lamp_buffer_union 		u
    WHERE ST_Intersects(r.geom, u.geom)
),
-- Стъпка 3: Групиране по район и резултат
grouped AS (
    SELECT
        district,
        SUM(total_m) AS total_len_m,
        SUM(lit_m) AS total_lit_m
    FROM road_lit_parts_lens
    GROUP BY district
)
select * from grouped;