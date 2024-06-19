/*
Replace the value in the DECLARE with what you want to search. 
Leave the % at the beginning and end to find words like it.
*/

DECLARE @column_name AS VARCHAR(100) = '%task%'

SELECT 
'clyde' as databaseName,
tc.name AS table_name,
SCHEMA_NAME(schema_id) AS schema_name,
cc.name AS column_name
FROM [BMSandusky_Clyde].sys.tables AS tc
INNER JOIN [BMSandusky_Clyde].sys.columns cc ON tc.OBJECT_ID = cc.OBJECT_ID
WHERE cc.name LIKE @column_name
and (tc.name Like ('tbl%') or tc.name LIKE ('sys%'))

UNION

SELECT 
'system' as databaseName,
ts.name AS table_name,
SCHEMA_NAME(schema_id) AS schema_name,
cs.name AS column_name
FROM [BMSandusky_System].sys.tables AS ts
INNER JOIN [BMSandusky_System].sys.columns cs ON ts.OBJECT_ID = cs.OBJECT_ID
WHERE cs.name LIKE @column_name
and (ts.name Like ('tbl%') or ts.name LIKE ('sys%'))

UNION

SELECT 
'woodville' as databaseName,
tw.name AS table_name,
SCHEMA_NAME(schema_id) AS schema_name,
cw.name AS column_name
FROM [BMSandusky_Woodville].sys.tables AS tw
INNER JOIN [BMSandusky_Woodville].sys.columns cw ON tw.OBJECT_ID = cw.OBJECT_ID
WHERE cw.name LIKE @column_name
and (tw.name Like ('tbl%') or tw.name LIKE ('sys%'))

--UNION

--SELECT 
--'probation' as databaseName,
--tp.name AS table_name,
--SCHEMA_NAME(schema_id) AS schema_name,
--cp.name AS column_name
--FROM [RockwareProbation0001].sys.tables AS tp
--INNER JOIN [RockwareProbation0001].sys.columns cp ON tp.OBJECT_ID = cp.OBJECT_ID
--WHERE cp.name LIKE @column_name
--and (tp.name Like ('tbl%') or tp.name LIKE ('sys%'))

UNION

SELECT 
'commonpleas' as databaseName,
tcp.name AS table_name,
SCHEMA_NAME(schema_id) AS schema_name,
ccp.name AS column_name
FROM [BMSandusky_CommonPleas].sys.tables AS tcp
INNER JOIN [BMSandusky_CommonPleas].sys.columns ccp ON tcp.OBJECT_ID = ccp.OBJECT_ID
WHERE ccp.name LIKE @column_name
and (tcp.name Like ('tbl%') or tcp.name LIKE ('sys%'))
ORDER BY databaseName, schema_name, table_name;
