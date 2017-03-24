------------------------------------------------------
--
-- Código destinado a dropar todas as tabelas do DB
--
------------------------------------------------------

BEGIN TRAN

DECLARE @nametable  VARCHAR (50),
        @sql        VARCHAR (65)

DECLARE cr_delete CURSOR FAST_FORWARD LOCAL FOR
SELECT T.name 
FROM (SELECT TBL.name, TBLP.nome 
      FROM TabelasPadrao TBLP 
      RIGHT JOIN sys.tables TBL 
      ON TBL.name = TBLP.nome WHERE TBL.schema_id = 1) AS T
WHERE T.nome is NULL 
OPEN cr_delete
    WHILE (1=1)
    BEGIN

        FETCH cr_delete INTO @nametable
        
        IF @@FETCH_STATUS <> 0
            BREAK
           
        SELECT @sql = 'DROP TABLE dbo.' + @nametable
        EXEC (@sql)

    END
CLOSE cr_delete
DEALLOCATE cr_delete

COMMIT