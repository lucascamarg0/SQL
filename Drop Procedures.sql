------------------------------------------------------
--
-- Código destinado a dropar todas as procedures do DB
--
------------------------------------------------------

--BEGIN TRAN

USE [EverDadosFood2_11]
go

DECLARE
    @nome_proc   VARCHAR(100),
    @str_sql        VARCHAR(max)

DECLARE cr_nome CURSOR FAST_FORWARD LOCAL FOR    
    SELECT name
    FROM sys.procedures 

OPEN cr_nome
    WHILE (1=1)
    BEGIN
        FETCH cr_nome INTO @nome_proc
    
    IF @@FETCH_STATUS <> 0
        BREAK
        
    SELECT @str_sql = 'DROP PROCEDURE dbo.' + @nome_proc
    PRINT (@str_sql)
    EXEC (@str_sql)
  
    END
CLOSE cr_nome
DEALLOCATE cr_nome

--COMMIT

