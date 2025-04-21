-- Анализ на осветлението на пътната мрежа
-- Стъпка 1: Създаване и обединяване на буфер 10м около лампите в добро състояние
WITH lamp_buffer_union AS (
    SELECT
        ST_Union(ST_Buffer(geom, 10)) AS geom
    FROM ul_osvetlenie
    WHERE condition = 'добро'
),

-- Стъпка 2: Пресичане на пътищата с буфера (намиране на осветените участъци)
road_lit_parts AS (
    SELECT
        r.id,
        r.geom,
        r.road_categ,
        r.road_name,
        ST_Intersection(r.geom, u.geom) AS lit_geom
    FROM municipality_roads_api r
    CROSS JOIN lamp_buffer_union u
    WHERE ST_Intersects(r.geom, u.geom)
),

-- Стъпка 3: Изчисляване на обща и осветена дължина за всеки път
road_lengths AS (
    SELECT
        r.id,
        r.road_categ,
        r.road_name,
        r.geom,
        ST_Length(r.geom)/1000.0 AS total_km,
        COALESCE(ST_Length(l.lit_geom)/1000.0, 0) AS lit_km
    FROM municipality_roads_api r
    LEFT JOIN road_lit_parts l ON r.id = l.id
),

-- Стъпка 4: Определяне на района за всеки път (по центроид)
roads_with_district AS (
    SELECT
        rl.*,
        a.obns_cyr AS district
    FROM road_lengths rl
    LEFT JOIN adm_rayoni a
        ON ST_Intersects(ST_Centroid(rl.geom), a.geom)
),

-- Стъпка 5: Групиране по район и категория
grouped AS (
    SELECT
        district,
        road_categ,
        SUM(total_km) AS total_km,
        SUM(lit_km) AS lit_km
    FROM roads_with_district
    GROUP BY district, road_categ
),

-- Стъпка 6: Качествена оценка на осветеността
final AS (
    SELECT
        *,
        CASE
            WHEN total_km = 0 THEN 0
            ELSE ROUND((100.0 * lit_km / total_km)::numeric, 2)
        END AS percent_lit,
        CASE
            WHEN total_km = 0 THEN 'няма данни'
            WHEN (lit_km / total_km) < 0.3 THEN 'лоша'
            WHEN (lit_km / total_km) < 0.7 THEN 'средна'
            ELSE 'добра'
        END AS quality
    FROM grouped
)

-- Стъпка 7: Краен резултат
SELECT
    district AS "Район",
    road_categ AS "Категория път",
    total_km AS "Обща дължина (км)",
    lit_km AS "Осветена дължина (км)",
    percent_lit AS "Процент осветеност",
    quality AS "Качествена оценка"
FROM final
ORDER BY district, road_categ;