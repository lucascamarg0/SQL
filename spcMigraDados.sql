USE [EverDadosFood2_11]
GO
/****** Object:  StoredProcedure [dbo].[spcMigraDados]    Script Date: 22/02/2017 10:10:44 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[spcMigraDados]
    @base_name VARCHAR (100)

AS
SET NOCOUNT ON
-- **********************************************************************
-- Data Criacao..: 24/05/2016   Autor: Lucas Soares
-- Versao 1.0....: Procedure para realizar a migração de todos os dados 
-- para outra base.
--
-- Data Alteracao: 21/09/2016   Autor: Lucas Soares
-- Versao 1.1....: Adicionada condição para zerar identitys ao falhar
-- TRY...CATCH de inserção de dados.
-- 
-- Data Alteracao: 22/02/2017   Autor: Lucas Soares
-- Versao 1.2....: Corrigida condição que zerava identitys, a mesma 
-- estava zerando das tabelas de base de origem, quando deveria ser da
-- destino
--
-- Obs.: Para realizar a migração é necessário que as duas bases estejam 
-- na mesma versão.
--
-- Comando de execução: EXEC spcMigraDados 'NomeBaseDestino'
-- **********************************************************************

BEGIN TRANSACTION

DECLARE @triggerant         TABLE (tabela  VARCHAR(250), trigger_name VARCHAR(250))
DECLARE @trigger            TABLE (comando VARCHAR(250))
DECLARE @migracao           TABLE (tabela  VARCHAR(250))
DECLARE @migracao_verif     TABLE (tabela  VARCHAR(250), contador TINYINT)

DECLARE
    @trigger_name   VARCHAR(250),
    @parent_tr      VARCHAR(25),
    @table_name     VARCHAR(250),
    @str_sql        VARCHAR(max),
    @str_columns    VARCHAR(max),
    @str_orderby    VARCHAR(max),
    @str_trigger    VARCHAR(max),
    @erro           SMALLINT
    
-- DESABILITA TRIGGERS

-- STRING COM COMANDO DINAMICO PARA RECEBER NOME DA BASE
SELECT @str_trigger =   'SELECT TBL.name tabela,
                        LTRIM(RTRIM(TGR.name)) objeto
                        FROM ' + @base_name + '.sys.triggers TGR
                        INNER JOIN ' + @base_name + '.sys.objects TBL ON TGR.parent_id = TBL.object_id
                        WHERE TGR.is_disabled = 0 AND schema_id = 1
                        ORDER BY TBL.name'

INSERT INTO @triggerant EXEC (@str_trigger)


-- CURSOR PARA DESATIVAR TRIGGERS
DECLARE cr_nome CURSOR FAST_FORWARD LOCAL FOR    
    SELECT  tabela, trigger_name FROM @triggerant

OPEN cr_nome
    WHILE (1=1)
    BEGIN
        FETCH cr_nome INTO @table_name, @trigger_name
    
    IF (@@FETCH_STATUS <> 0) BREAK
        
    -- DESABILITANDO TRIGGERS
    SELECT @str_sql = 'ALTER TABLE ' + @base_name + '.dbo.' + @table_name + ' DISABLE TRIGGER ' + @trigger_name
    PRINT @str_sql
    EXEC (@str_sql)
    
    -- SALVANDO COMANDO PARA HABILITÁ-LAS POSTERIORMENTE
    SELECT @str_sql = 'ALTER TABLE ' + @base_name + '.dbo.' + @table_name + ' ENABLE TRIGGER ' + @trigger_name
    INSERT INTO @trigger
    SELECT @str_sql
  
    END
CLOSE cr_nome
DEALLOCATE cr_nome


-- MIGRAÇÃO

-- INSERT DAS TABELAS PADRÕES EM DUAS TABELAS DE CONTROLE
INSERT INTO @migracao SELECT name FROM sys.objects 
                       WHERE type = 'U' AND schema_id = 1 
                       ORDER BY name
                      
INSERT INTO @migracao_verif(tabela, contador) SELECT tabela, 0 FROM @migracao

-- CURSOR DE MIGRAÇÃO
WHILE EXISTS (SELECT 1 FROM @migracao)
BEGIN
    DECLARE cr_migracao CURSOR FAST_FORWARD LOCAL FOR
    SELECT LTRIM(RTRIM(tabela)) FROM @migracao

    OPEN cr_migracao

    WHILE (1=1)
    BEGIN
        FETCH cr_migracao INTO @table_name

        IF (@@FETCH_STATUS <> 0) BREAK
        
        SELECT @str_orderby = ''
        SELECT @str_columns = ''

        --LISTA COLUNAS NÃO IDENTITY
        SELECT @str_columns = @str_columns + c.name + ',' 
          FROM sys.objects O
         INNER JOIN sys.columns C ON C.object_id = O.object_id
         WHERE O.type = 'U' 
           AND C.is_identity = 0 
           AND O.name = @table_name
         ORDER BY C.column_id 
        
        IF(LEN(@str_columns) > 0)
        BEGIN
            SELECT @str_columns = SUBSTRING(@str_columns,1,LEN(@str_columns)-1)
        END
        
        --REALIZA ORDER BY COM BASE NA PK DA TABELA
        SELECT @str_orderby = @str_orderby + K.COLUMN_NAME + ',' 
          FROM INFORMATION_SCHEMA.KEY_COLUMN_USAGE K
         WHERE TABLE_NAME = @table_name
           AND CONSTRAINT_NAME = (SELECT name 
                                    FROM SYSOBJECTS As U
                                   WHERE K.TABLE_NAME = OBJECT_NAME(U.Parent_Obj) 
                                     AND U.XTYPE = 'PK')
         ORDER BY TABLE_SCHEMA, TABLE_NAME, ORDINAL_POSITION
        
        IF(LEN(@str_orderby) > 0)
        BEGIN
            SELECT @str_orderby = SUBSTRING(@str_orderby,1,LEN(@str_orderby)-1)
            SELECT @str_orderby = ' ORDER BY ' + @str_orderby
        END
        
        --TRY DE MIGRAÇÃO
        BEGIN
            BEGIN TRY
                SELECT @str_sql = 'INSERT INTO ' + @base_name + '.dbo.' + @table_name + 
                                  '(' + @str_columns + ')' + ' SELECT ' + @str_columns + 
                                  ' FROM ' + @table_name + @str_orderby 
                                 				
                EXEC (@str_sql)
                
                DELETE FROM @migracao WHERE tabela = @table_name
                DELETE FROM @migracao_verif WHERE tabela = @table_name
                
                PRINT 'INSERT INTO ' + @base_name + '.dbo.' + @table_name            
                SELECT @erro = 0
            END TRY
            BEGIN CATCH
                -- O SELECT ABAIXO SERVE PARA DETECTAR PROBLEMAS NA MIGRAÇÃO
                SELECT
                ERROR_NUMBER() AS NumeroErro,
                --ERROR_SEVERITY() AS ErrorSeverity,
                --ERROR_STATE() AS ErrorState,
                --ERROR_PROCEDURE() AS ErrorProcedure,
                --ERROR_LINE() AS LinhaErro,
                ERROR_MESSAGE() AS MensagemErro,
                @table_name AS NomeTabela 
                
                -- CONTADOR PARA CONTROLE DE LOOP NA TABELA
                UPDATE @migracao_verif SET contador = contador+1 WHERE tabela = @table_name
                
                
                --SE A TABELA CONTIVER CAMPOS IDENTITY O MESMO SERÁ ZERADO
                IF(@table_name IN (SELECT OBJECT_NAME(object_id) 
                                     FROM SYS.IDENTITY_COLUMNS 
                                    WHERE object_id IN (SELECT object_id 
                                                          FROM SYS.OBJECTS 
                                                         WHERE TYPE = 'U')))
                BEGIN
                    --ROTINA ABAIXO EXECUTA PROCEDURE PARA ZERAR IDENTITY
                    SELECT @str_sql = @base_name + '.dbo.spcZeraIdentity ''' + @table_name + ''''
                    EXEC (@str_sql)
                END

                SELECT @erro = MIG.contador 
                  FROM @migracao_verif MIG
                 WHERE MIG.tabela = @table_name
                
                -- IF COM VERIFICAÇÃO SE MIGRAÇÃO ENTROU EM LOOP INFINITO
                IF(@erro >= 50) 
                BEGIN
                    PRINT 'FALHA NA MIGRAÇÃO, ERRO DE INSERÇÃO NA TABELA ' + @table_name
                    PRINT 'AS ALTERAÇÕES FORAM DESFEITAS'
                    ROLLBACK TRANSACTION
                    RETURN
                END
                
            END CATCH
        END
        
    END
    CLOSE cr_migracao
    DEALLOCATE cr_migracao
    
END

IF (@erro = 0) PRINT 'DADOS MIGRADOS'


--HABILITA TRIGGERS

DECLARE cr_enable_tr CURSOR FAST_FORWARD LOCAL FOR
SELECT LTRIM(RTRIM(comando)) FROM @trigger

OPEN cr_enable_tr

WHILE (1=1)
BEGIN
    FETCH cr_enable_tr INTO @str_sql

    IF (@@FETCH_STATUS <> 0) BREAK
    
    PRINT (@str_sql)
    EXEC (@str_sql)

END
CLOSE cr_enable_tr
DEALLOCATE cr_enable_tr

COMMIT

GO
