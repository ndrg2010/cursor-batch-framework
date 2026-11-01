/**
 * @description Unit tests for CursorBatchQueryProbe.
 * @group CursorBatchFramework
 */
@IsTest
private without sharing class CursorBatchQueryProbeTest {

    @IsTest
    static void buildProbeQuery_dropsOrderByAndAddsLimit() {
        Assert.areEqual(
            'SELECT Id, Name FROM Account LIMIT 1',
            CursorBatchQueryProbe.buildProbeQuery('SELECT Id, Name FROM Account ORDER BY Name'),
            'ORDER BY should be dropped and LIMIT 1 appended; the select list is kept'
        );
    }

    @IsTest
    static void buildProbeQuery_overridesExistingLimitAndKeepsOffset() {
        Assert.areEqual(
            'SELECT Name FROM Account WHERE Name = \'x\' LIMIT 1 OFFSET 10',
            CursorBatchQueryProbe.buildProbeQuery('SELECT Name FROM Account WHERE Name = \'x\' ORDER BY Name DESC NULLS LAST LIMIT 50 OFFSET 10'),
            'LIMIT should become 1 and OFFSET should be kept'
        );
    }

    @IsTest
    static void buildProbeQuery_keepsLimitZero() {
        Assert.areEqual(
            'SELECT Id FROM Account LIMIT 0',
            CursorBatchQueryProbe.buildProbeQuery('SELECT Id FROM Account LIMIT 0'),
            'LIMIT 0 matches nothing and must stay 0'
        );
    }

    @IsTest
    static void buildProbeQuery_insertsLimitBeforeOffsetAndTrailingClauses() {
        Assert.areEqual(
            'SELECT Id FROM Account WHERE Name != null LIMIT 1 OFFSET 5',
            CursorBatchQueryProbe.buildProbeQuery('SELECT Id FROM Account WHERE Name != null OFFSET 5'),
            'LIMIT must precede OFFSET'
        );
        Assert.areEqual(
            'SELECT Id FROM Account WHERE IsDeleted = true LIMIT 1 ALL ROWS',
            CursorBatchQueryProbe.buildProbeQuery('SELECT Id FROM Account WHERE IsDeleted = true ORDER BY Name ALL ROWS'),
            'LIMIT must precede ALL ROWS, which is kept'
        );
        Assert.areEqual(
            'SELECT Id FROM Account LIMIT 1 FOR UPDATE',
            CursorBatchQueryProbe.buildProbeQuery('SELECT Id FROM Account FOR UPDATE'),
            'LIMIT must precede FOR UPDATE, which is kept'
        );
    }

    @IsTest
    static void buildProbeQuery_keepsWithClause() {
        Assert.areEqual(
            'SELECT Name FROM Account WHERE Name != null WITH SYSTEM_MODE LIMIT 1',
            CursorBatchQueryProbe.buildProbeQuery('SELECT Name FROM Account WHERE Name != null WITH SYSTEM_MODE ORDER BY Name ASC NULLS FIRST'),
            'WITH clauses decide which rows are visible and must be kept verbatim'
        );
    }

    @IsTest
    static void buildProbeQuery_ignoresClausesInsideSubqueries() {
        String query = 'SELECT Id, (SELECT Id FROM Contacts ORDER BY Name LIMIT 5) FROM Account ' +
            'WHERE Id IN (SELECT AccountId FROM Contact ORDER BY Name LIMIT 10) ORDER BY Name';
        Assert.areEqual(
            'SELECT Id, (SELECT Id FROM Contacts ORDER BY Name LIMIT 5) FROM Account ' +
                'WHERE Id IN (SELECT AccountId FROM Contact ORDER BY Name LIMIT 10) LIMIT 1',
            CursorBatchQueryProbe.buildProbeQuery(query),
            'Only the top-level ORDER BY and LIMIT should change'
        );
    }

    @IsTest
    static void buildProbeQuery_ignoresKeywordsInsideStringLiterals() {
        String query = 'SELECT Id FROM Account WHERE Name = \'Order by  \\\' LIMIT 5\' AND Description != \'FROM\'';
        Assert.areEqual(
            query + ' LIMIT 1',
            CursorBatchQueryProbe.buildProbeQuery(query),
            'Literals, including spacing and an escaped quote, should be untouched'
        );
    }

    @IsTest
    static void buildProbeQuery_ignoresFieldNamesThatContainKeywords() {
        Assert.areEqual(
            'SELECT Name FROM Account WHERE Offset_Days__c > 1 AND Order_Limit__c = null LIMIT 1',
            CursorBatchQueryProbe.buildProbeQuery(
                'SELECT Name FROM Account WHERE Offset_Days__c > 1 AND Order_Limit__c = null'
            ),
            'Field names that contain keywords should be kept'
        );
    }

    @IsTest
    static void buildProbeQuery_handlesLowercaseAndLineBreaks() {
        Assert.areEqual(
            'select id, name\n from account\n where name != null\n LIMIT 1',
            CursorBatchQueryProbe.buildProbeQuery('select id, name\n from account\n where name != null\n order  by name\n limit 5'),
            'Keywords should match case-insensitively across whitespace'
        );
    }

    @IsTest
    static void buildProbeQuery_returnsNullWhenItCannotRewrite() {
        Assert.isNull(CursorBatchQueryProbe.buildProbeQuery(null), 'Null query should yield no probe');
        Assert.isNull(CursorBatchQueryProbe.buildProbeQuery('   '), 'Blank query should yield no probe');
        Assert.isNull(CursorBatchQueryProbe.buildProbeQuery('SELECT Id'), 'Query without FROM should yield no probe');
        Assert.isNull(CursorBatchQueryProbe.buildProbeQuery('SELECT Id FROM Account LIMIT :max'), 'Non-numeric LIMIT should yield no probe');
    }
}
