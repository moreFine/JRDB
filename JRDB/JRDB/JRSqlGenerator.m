//
//  JRSqlGenerator.m
//  JRDB
//
//  Created by JMacMini on 16/5/10.
//  Copyright © 2016年 Jrwong. All rights reserved.
//

#import "JRDBMgr.h"
#import "JRDBChain.h"
#import <FMDB/FMDB.h>
#import "NSObject+JRDB.h"
#import "JRReflectUtil.h"
#import "JRSqlGenerator.h"
#import "NSObject+Reflect.h"
#import "JRActivatedProperty.h"


@implementation JRSql

@synthesize sqlString = _sqlString;
@synthesize args = _args;

+ (instancetype)sql:(NSString *)sql args:(NSArray *)args {
    JRSql *jrsql = [[self alloc] init];
    jrsql->_sqlString = sql;
    jrsql->_args = [args mutableCopy];
    return jrsql;
}

- (NSMutableArray *)args {
    if (!_args) {
        _args = [NSMutableArray array];
    }
    return _args;
}

- (NSString *)description {
    return _sqlString ? _sqlString : @"";
}

@end


void SqlLog(id sql) {
#ifdef DEBUG
    if ([JRDBMgr shareInstance].debugMode) {
        NSLog(@"%@", sql);
    }
#endif
}


@implementation JRSqlGenerator

+ (NSString *)getTableNameForClazz:(Class<JRPersistent>)clazz {
    return [clazz jr_tableName];
}

// create table 'tableName' (ID text primary key, 'p1' 'type1')
+ (JRSql *)createTableSql4Clazz:(Class<JRPersistent>)clazz table:(NSString * _Nullable)table{

    NSArray<JRActivatedProperty *> *ap = [clazz jr_activatedProperties];


    NSString *tableName  = table ?: [self getTableNameForClazz:clazz];
    NSMutableString *sql = [NSMutableString string];
    
    [sql appendFormat:@"create table if not exists %@ (_ID text primary key ", tableName];

    [ap enumerateObjectsUsingBlock:^(JRActivatedProperty * _Nonnull prop, NSUInteger idx, BOOL * _Nonnull stop) {
        // 如果是关键字'ID' 或 '_ID' 则继续循环
        if (isID(prop.ivarName)) {return;}

        switch (prop.relateionShip) {
            case JRRelationNormal:
            case JRRelationOneToOne:
            case JRRelationChildren:
            {
                [sql appendFormat:@", %@ %@", prop.dataBaseName, prop.dataBaseType];
                break;
            }
            default:
                break;
        }
    }];

    [sql appendString:@");"];
    JRSql *jrsql = [JRSql sql:sql args:nil];
    SqlLog(jrsql);
    return jrsql;
}

// {alter 'tableName' add column xx}
+ (NSArray<JRSql *> *)updateTableSql4Clazz:(Class<JRPersistent>)clazz inDB:(FMDatabase *)db table:(NSString * _Nullable)table {
    NSString *tableName  = table ?: [self getTableNameForClazz:clazz];
    // 检测表是否存在, 不存在则直接返回创建表语句
    if (![db tableExists:tableName]) { return @[[self createTableSql4Clazz:clazz table:tableName]]; }

    NSArray<JRActivatedProperty *> *ap = [clazz jr_activatedProperties];
    NSMutableArray *sqls = [NSMutableArray array];

    [ap enumerateObjectsUsingBlock:^(JRActivatedProperty * _Nonnull prop, NSUInteger idx, BOOL * _Nonnull stop) {
        // 如果是关键字'ID' 或 '_ID' 则继续循环
        if (isID(prop.ivarName)) {return;}
        if ([db columnExists:prop.dataBaseName inTableWithName:tableName]) { return; }

        JRSql *jrsql;
        switch (prop.relateionShip) {
            case JRRelationNormal:
            case JRRelationOneToOne:
            case JRRelationChildren:
            {
                jrsql = [JRSql sql:[NSString stringWithFormat:@"alter table %@ add column %@ %@;", tableName, prop.dataBaseName, prop.dataBaseType] args:nil];
                [sqls addObject:jrsql];
                break;
            }
            default: return;
        }
    }];

    
    SqlLog(sqls);
    return sqls;
}


+ (JRSql *)dropTableSql4Clazz:(Class<JRPersistent>)clazz table:(NSString * _Nullable)table{
    NSString *sql = [NSString stringWithFormat:@"drop table if exists %@ ;", table ?: [self getTableNameForClazz:clazz]];
    JRSql *jrsql = [JRSql sql:sql args:nil];
    SqlLog(jrsql);
    return jrsql;
}

// insert into tablename (_ID) values (?)
+ (JRSql *)sql4Insert:(id<JRPersistent>)obj toDB:(FMDatabase * _Nonnull)db table:(NSString * _Nullable)table {
    
    NSString *tableName = table ?: [self getTableNameForClazz:[obj class]];
    NSArray<JRActivatedProperty *> *ap = [JRReflectUtil activitedProperties4Clazz:[obj class]];
    NSMutableArray *argsList = [NSMutableArray array];
    NSMutableString *sql     = [NSMutableString string];
    NSMutableString *sql2    = [NSMutableString string];
    
    [sql appendFormat:@" insert into %@ ('_ID' ", tableName];
    [sql2 appendFormat:@" values ( ? "];
    
    [ap enumerateObjectsUsingBlock:^(JRActivatedProperty * _Nonnull prop, NSUInteger idx, BOOL * _Nonnull stop) {
        // 如果是关键字'ID' 或 '_ID' 则继续循环
        if (isID(prop.ivarName)) {return;}
        if (![db columnExists:prop.dataBaseName inTableWithName:tableName]) { return; }
        
        // 拼接语句
        [sql appendFormat:@" , %@", prop.dataBaseName];
        [sql2 appendFormat:@" , ?"];
        
        id value;
        switch (prop.relateionShip) {
            case JRRelationNormal:
            {
                value = [(NSObject *)obj valueForKey:prop.propertyName];
                break;
            }
            case JRRelationOneToOne:
            {
                NSObject<JRPersistent> *sub = [((NSObject *)obj) valueForKey:prop.propertyName];
                value = [sub ID];
                break;
            }
            case JRRelationChildren:
            {
                NSString *parentID = [((NSObject *)obj) jr_parentLinkIDforKey:prop.propertyName];
                value = parentID;
                break;
            }
            default: return;
        }
        
        // 空值转换
        if (!value) { value = [NSNull null]; }
        // 添加参数
        [argsList addObject:value];
        
    }];
    
    
    
    [sql appendString:@")"];
    [sql2 appendString:@");"];
    [sql appendString:sql2];

    JRSql *jrsql = [JRSql sql:sql args:argsList];
    SqlLog(jrsql);
    return jrsql;
}

+ (JRSql *)sql4Delete:(id<JRPersistent>)obj table:(NSString * _Nullable)table {
    NSString *sql = [NSString stringWithFormat:@"delete from %@ where %@ = ? ;", table ?: [self getTableNameForClazz:[obj class]], [[obj class] jr_primaryKey]];
    JRSql *jrsql = [JRSql sql:sql args:nil];
    SqlLog(jrsql);
    return jrsql;

}

+ (JRSql *)sql4DeleteAll:(Class<JRPersistent>)clazz table:(NSString * _Nullable)table {
    NSString *sql = [NSString stringWithFormat:@"delete from %@", table ?: [self getTableNameForClazz:clazz]];
    JRSql *jrsql = [JRSql sql:sql args:nil];
    SqlLog(jrsql);
    return jrsql;

}

// update 'tableName' set name = 'abc' where xx = xx
+ (JRSql *)sql4Update:(id<JRPersistent>)obj columns:(NSArray<NSString *> *)columns toDB:(FMDatabase * _Nonnull)db table:(NSString * _Nullable)table {
    
    NSArray<JRActivatedProperty *> *ap = [[obj class] jr_activatedProperties];
    
    NSString *tableName      = table ?: [self getTableNameForClazz:[obj class]];
    NSMutableArray *argsList = [NSMutableArray array];
    NSMutableString *sql     = [NSMutableString string];
    
    [sql appendFormat:@" update %@ set ", tableName];
    
    [ap enumerateObjectsUsingBlock:^(JRActivatedProperty * _Nonnull prop, NSUInteger idx, BOOL * _Nonnull stop) {
        // 如果是关键字'ID' 或 '_ID' 则继续循环
        if (isID(prop.ivarName)) {return;}
        // 是否在指定更新列中
        if (columns.count && ![columns containsObject:prop.ivarName]) { return; }
        if (![db columnExists:prop.dataBaseName inTableWithName:tableName]) { return; }
        
        id value;
        switch (prop.relateionShip) {
            case JRRelationNormal:
            {
                value = [(NSObject *)obj valueForKey:prop.propertyName];
                break;
            }
            case JRRelationOneToOne:
            {
                NSObject<JRPersistent> *sub = [((NSObject *)obj) valueForKey:prop.propertyName];
                if (sub && ![sub ID]) {// 如果有新的子对象，则不更新
                    return;
                }
                [((NSObject *)obj) jr_setSingleLinkID:[sub ID] forKey:prop.propertyName];
                value = [sub ID];
                break;
            }
            case JRRelationChildren:
            {
                NSString *parentID = [((NSObject *)obj) jr_parentLinkIDforKey:prop.propertyName];
                value = parentID;
                break;
            }
            default: return;
        }
        [sql appendFormat:@" %@ = ?,", prop.dataBaseName];
        // 空值转换
        if (!value) { value = [NSNull null]; }
        // 添加参数
        [argsList addObject:value];

    }];
    
    
    if ([sql hasSuffix:@","]) {
        sql = [[sql substringToIndex:sql.length - 1] mutableCopy];
    }
    
    [sql appendFormat:@" where %@ = ? ;", [[obj class] jr_primaryKey]];

    JRSql *jrsql = [JRSql sql:sql args:argsList];
    SqlLog(jrsql);
    return jrsql;

}

+ (JRSql * _Nonnull)sql4GetByIDWithClazz:(Class<JRPersistent> _Nonnull)clazz ID:(NSString *)ID table:(NSString * _Nullable)table {
    NSString *condition = [NSString stringWithFormat:@"_ID=?"];
    return [self sql4GetColumns:nil
                    byCondition:condition
                         params:@[ID]
                          clazz:clazz
                        groupBy:nil
                        orderBy:nil
                          limit:nil
                         isDesc:NO
                          table:nil];
}

+ (JRSql *)sql4GetByPrimaryKeyWithClazz:(Class<JRPersistent>)clazz primaryKey:(id _Nonnull)primaryKey table:(NSString * _Nullable)table {

    NSString *condition = [NSString stringWithFormat:@"%@=?", [clazz jr_primaryKey]];
    return [self sql4GetColumns:nil
                    byCondition:condition
                         params:@[primaryKey]
                          clazz:clazz
                        groupBy:nil
                        orderBy:nil
                          limit:nil
                         isDesc:NO
                          table:nil];
}

+ (JRSql *)sql4FindAll:(Class<JRPersistent>)clazz orderby:(NSString *)orderby isDesc:(BOOL)isDesc table:(NSString * _Nullable)table {
    return [self sql4GetColumns:nil
                    byCondition:nil
                         params:nil
                          clazz:clazz
                        groupBy:nil
                        orderBy:nil
                          limit:nil
                         isDesc:NO
                          table:nil];
}

#pragma mark - convenience

+ (JRSql *)sql4CountByPrimaryKey:(id)pk clazz:(Class<JRPersistent>)clazz table:(NSString * _Nullable)table {
    NSString *sql = [NSString stringWithFormat:@"select count(1) from %@ where %@ = ?", table ?: [self getTableNameForClazz:clazz], [clazz jr_primaryKey]];
    JRSql *jrsql = [JRSql sql:sql args:@[pk]];
    SqlLog(jrsql);
    return jrsql;
}

+ (JRSql *)sql4CountByID:(NSString *)ID clazz:(Class<JRPersistent>)clazz table:(NSString * _Nullable)table {
    NSString *sql = [NSString stringWithFormat:@"select count(1) from %@ where _ID = ?", table ?: [self getTableNameForClazz:clazz]];
    JRSql *jrsql = [JRSql sql:sql args:@[ID]];
    SqlLog(jrsql);
    return jrsql;
}

+ (JRSql *)sql4GetColumns:(NSArray<NSString *> *)columns
              byCondition:(NSString *)condition
                   params:(NSArray *)params
                    clazz:(Class<JRPersistent>)clazz
                  groupBy:(NSString *)groupBy
                  orderBy:(NSString *)orderBy
                    limit:(NSString *)limit
                   isDesc:(BOOL)isDesc
                    table:(NSString *)table
{

    NSMutableArray *argList = [NSMutableArray array];
    NSString *tableName = table ?: [self getTableNameForClazz:clazz];
    NSMutableString *sqlString = [NSMutableString string];

    if (columns.count) {
        [sqlString appendString:@" select "];
        [columns enumerateObjectsUsingBlock:^(NSString * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            idx ? [sqlString appendFormat:@", %@ ", obj] : [sqlString appendFormat:@"%@", obj];
        }];
    } else {
        [sqlString appendString:@" select * "];
    }
    
    [sqlString appendFormat:@" from %@ where 1=1 ", tableName];

    if (condition) {
        [sqlString appendFormat:@"%@ ", condition];
    }

    if (params.count) {
        [argList addObjectsFromArray:params];
    }

    // group
    if (groupBy.length) { [sqlString appendFormat:@" group by %@ ", groupBy]; }
    // orderby
    if (orderBy.length) { [sqlString appendFormat:@" order by %@ ", orderBy]; }
    // desc asc
    if (isDesc && orderBy.length) {[sqlString appendString:@" desc "];}
    // limit
    if (limit.length) { [sqlString appendFormat:@" %@ ", limit]; }

    [sqlString appendString:@";"];

    JRSql *jrsql = [JRSql sql:sqlString args:argList];
    SqlLog(jrsql);
    return jrsql;

}

#pragma mark - private method
+ (NSString *)typeWithEncodeName:(NSString *)encode {
    if (strcmp(encode.UTF8String, @encode(int)) == 0
        || strcmp(encode.UTF8String, @encode(unsigned int)) == 0
        || strcmp(encode.UTF8String, @encode(long)) == 0
        || strcmp(encode.UTF8String, @encode(unsigned long)) == 0
        ) {
        return @"INTEGER";
    }
    if ([encode isEqualToString:[NSString stringWithUTF8String:@encode(float)]]
        ||[encode isEqualToString:[NSString stringWithUTF8String:@encode(double)]]
        ) {
        return @"REAL";
    }
    if ([encode rangeOfString:@"String"].length) {
        return @"TEXT";
    }
    if ([encode rangeOfString:@"NSNumber"].length) {
        return @"REAL";
    }
    if ([encode rangeOfString:@"NSData"].length) {
        return @"BLOB";
    }
    if ([encode rangeOfString:@"NSDate"].length) {
        return @"TIMESTAMP";
    }
    return nil;
}

+ (BOOL)isIgnoreProperty:(NSString *)property inClazz:(Class<JRPersistent>)clazz {
    NSArray *excludes = [clazz jr_excludePropertyNames];
    return [excludes containsObject:property] || isID(property);
}



@end


@implementation JRSqlGenerator (Chain)

+ (JRSql *)sql4Chain:(JRDBChain *)chain {
    
    NSMutableString *sqlString = [NSMutableString string];
    NSMutableArray *argList = [NSMutableArray array];
    
    [sqlString appendString:@" select "];
    
    if (chain.operation == CSelectCount) {
        [sqlString appendString:@" count(1) "];
    } else if (chain.selectColumns.count) {
        [chain.selectColumns enumerateObjectsUsingBlock:^(NSString * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            idx ? [sqlString appendFormat:@", %@ ", obj] : [sqlString appendFormat:@"%@", obj];
        }];
    } else {
        [sqlString appendString:@" * "];
    }
    
    [sqlString appendString:@" from "];
    
    if (chain.subChain) {
        JRSql *sql = [self sql4Chain:chain.subChain];
        [sqlString appendFormat:@" (%@) ", sql.sqlString];
        [argList addObjectsFromArray:sql.args];
    } else {
        [sqlString appendString:chain.tableName ?: [self getTableNameForClazz:chain.targetClazz]];
    }
    
    [sqlString appendString:@" where 1=1 "];
    
    NSAssert(!(chain.whereString.length && chain.whereId.length), @"where condition should not hold more than one!!!");
    NSAssert(!(chain.whereString.length && chain.wherePK), @"where condition should not hold more than one!!!");
    NSAssert(!(chain.whereId.length && chain.wherePK), @"where condition should not hold more than one!!!");
    
    if (chain.whereString.length) {
        [sqlString appendFormat:@" and (%@)", chain.whereString];
        [argList addObjectsFromArray:chain.parameters];
    } else if (chain.whereId.length) {
        [sqlString appendFormat:@" and ( _id = ?)"];
        [argList addObject:chain.whereId];
    } else if (chain.wherePK) {
        NSString *pk = [chain.targetClazz jr_primaryKey];
        [sqlString appendFormat:@" and ( %@ = ?)", pk];
        [argList addObject:chain.wherePK];
    }
    
    // group
    if (chain.groupBy.length) { [sqlString appendFormat:@" group by %@ ", chain.groupBy]; }
    // orderby
    if (chain.orderBy.length) { [sqlString appendFormat:@" order by %@ ", chain.orderBy]; }
    // desc asc
    if (chain.isDesc && chain.orderBy.length) {[sqlString appendString:@" desc "];}
    // limit
    if (chain.limitString.length) { [sqlString appendFormat:@" %@ ", chain.limitString]; }
    
    // 有可能是子查询，不能加 『;』
//    [sqlString appendString:@";"];
    
    JRSql *jrsql = [JRSql sql:sqlString args:argList];
    SqlLog(jrsql);
    return jrsql;
}

@end


