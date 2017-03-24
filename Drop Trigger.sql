------------------------------------------------------
--
-- Código destinado a dropar todas as triggers do DB
--
------------------------------------------------------

DECLARE
    @nome_TGR   VARCHAR(100),
    @str_sql        VARCHAR(max)

DECLARE cr_nome CURSOR FAST_FORWARD LOCAL FOR    
    SELECT
    LTRIM(RTRIM(TGR.name))
    FROM sys.triggers TGR

OPEN cr_nome
    WHILE (1=1)
    BEGIN
        FETCH cr_nome INTO @nome_TGR
    
    IF @@FETCH_STATUS <> 0
        BREAK
        
    SELECT @str_sql = 'DROP TRIGGER ' + @nome_TGR
    PRINT (@str_sql)
    EXEC (@str_sql)
  
    END
CLOSE cr_nome
DEALLOCATE cr_nome

SELECT * FROM SYS.TRIGGERS