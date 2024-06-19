DECLARE
@search_int      INT,
@table_name      SYSNAME,
@table_id        INT,
@column_name     SYSNAME,
@sql_string      VARCHAR(2000)

SET @search_int = 1972150    -- CHANGE SEARCH VALUE HERE

DECLARE tables_cur CURSOR FOR 
SELECT ss.name +'.'+ so.name [name], object_id 
FROM sys.objects so 
INNER JOIN sys.schemas ss ON so.schema_id = ss.schema_id 
WHERE type = 'U'

OPEN tables_cur

FETCH NEXT FROM tables_cur INTO @table_name, @table_id

WHILE (@@FETCH_STATUS = 0)
BEGIN
    DECLARE columns_cur CURSOR FOR 
    SELECT name 
    FROM sys.columns 
    WHERE object_id = @table_id 
    AND system_type_id = 56  -- System type ID for INT

    OPEN columns_cur

    FETCH NEXT FROM columns_cur INTO @column_name
    WHILE (@@FETCH_STATUS = 0)
    BEGIN
        SET @sql_string = 'IF EXISTS (SELECT * FROM ' + @table_name + ' WHERE [' + @column_name + '] = ' + CAST(@search_int AS VARCHAR(10)) + ') PRINT ''' + @table_name + ', ' + @column_name + ''''

        EXECUTE(@sql_string)

        FETCH NEXT FROM columns_cur INTO @column_name
    END

    CLOSE columns_cur
    DEALLOCATE columns_cur

    FETCH NEXT FROM tables_cur INTO @table_name, @table_id

END

CLOSE tables_cur
DEALLOCATE tables_cur

