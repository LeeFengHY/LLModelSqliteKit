//
//  LLModelSqlite.m
//  LLModelSqliteKit
//
//  Created by QFWangLP on 2017/2/13.
//  Copyright © 2017年 LeeFengHY. All rights reserved.
//

#import "LLModelSqlite.h"
#import <objc/runtime.h>
#import <sqlite3.h>
#import <objc/message.h>
#import <UIKit/UIKit.h>


#define String_LL      (@"TEXT")
#define Int_LL         (@"INTERGER")
#define Boolean_LL     (@"INTERGER")
#define Double_LL      (@"DOUBLE")
#define Float_LL       (@"DOUBLE")
#define Char_LL        (@"NVARCHAR")
#define Model_LL       (@"INTERGER")
#define Data_LL        (@"BLOB")

typedef NS_OPTIONS(NSInteger, LL_FieldType){
    _String     =       1 << 0,
    _Int        =       1 << 1,
    _Boolean    =       1 << 2,
    _Double     =       1 << 3,
    _Float      =       1 << 4,
    _Char       =       1 << 5,
    _Number     =       1 << 6,
    _Model      =       1 << 7,
    _Data       =       1 << 8
};
typedef NS_OPTIONS(NSInteger, LL_QueryType){
    _Where      =       1 << 0,
    _Order      =       1 << 1,
    _Limit      =       1 << 2,
    _WhereOrder =       1 << 3,
    _OrderLimit =       1 << 4,
    _WhereOrderLimit =  1 << 5,
    _WhereLimit =       1 << 6
};

static sqlite3 * _ll_database;
static NSInteger _NO_HANDLE_KEY_ID = -2;

@interface LL_PropertyInfo : NSObject

@property (nonatomic, assign, readonly) LL_FieldType type;
@property (nonatomic, copy, readonly)   NSString * name;
@property (nonatomic, assign, readonly) SEL getter;
@property (nonatomic, assign, readonly) SEL setter;
@end

@implementation LL_PropertyInfo

- (LL_PropertyInfo *)initWithType:(LL_FieldType)type propertyName:(NSString *)property_name
{
    self = [super init];
    if ( self) {
        _name = property_name.mutableCopy;
        _type = type;
        _setter = NSSelectorFromString([NSString stringWithFormat:@"set%@%@",[property_name substringToIndex:1].uppercaseString,[property_name substringFromIndex:1]]);
        _getter = NSSelectorFromString(property_name);
        
    }
    return self;
}

@end

@interface LLModelSqlite ()

@property (nonatomic, strong) NSMutableDictionary *sub_model_info;

/**
 线程锁 保证线程安全
 */
@property (nonatomic, strong) dispatch_semaphore_t dsema;
@end
@implementation LLModelSqlite

- (LLModelSqlite *)init
{
    self = [super init];
    if ( self) {
        _sub_model_info = [NSMutableDictionary dictionary];
        _dsema = dispatch_semaphore_create(1);
    }
    return  self;
}
+ (LLModelSqlite *)shareInstance
{
    static LLModelSqlite *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[LLModelSqlite alloc] init];
    });
    return instance;
}
+ (NSString *)databaseCacheDirectory
{
    return [NSString stringWithFormat:@"%@/Library/Caches/LLSqlite/",NSHomeDirectory()];
}

+ (NSDictionary *)parserModelObjectFieldsWithModelClass:(Class)modelClass
{
    NSMutableDictionary *fields = [NSMutableDictionary new];
    unsigned int property_count = 0;
    objc_property_t *propertys = class_copyPropertyList(modelClass, &property_count);
    for (int i = 0; i < property_count; i++) {
        objc_property_t property_t = propertys[i];
        const char *property_name = property_getName(property_t);
        const char *property_attributes = property_getAttributes(property_t);
        NSString *property_name_string = [NSString stringWithUTF8String:property_name];
        NSString *property_attributes_string = [NSString stringWithUTF8String:property_attributes];
        //转义字符\，得到"（双引号）-T@"NSDictionary",C,N,V_dict1
        NSArray *property_attributes_list = [property_attributes_string componentsSeparatedByString:@"\""];
        if (property_attributes_list.count == 1) {
            //base type
            LL_FieldType type = [self parserFieldTypeWithAttribute:property_attributes_list[0]];
            LL_PropertyInfo *property_info = [[LL_PropertyInfo alloc] initWithType:type propertyName:property_name_string];
            [fields setObject:property_info forKey:property_name_string];
        }else{
            //reference type -- NSDictionary等等
            Class class_type = NSClassFromString(property_attributes_list[1]);
            LL_PropertyInfo *property_info = nil;
            if (class_type == [NSNumber class]) {
                property_info = [[LL_PropertyInfo alloc] initWithType:_Number propertyName:property_name_string];
            }else if (class_type == [NSString class]){
                property_info = [[LL_PropertyInfo alloc] initWithType:_String propertyName:property_name_string];
            }else if (class_type == [NSData class]){
                property_info = [[LL_PropertyInfo alloc] initWithType:_Data propertyName:property_name_string];
            }else if (class_type == [NSArray class] ||
                      class_type == [NSDictionary class] ||
                      class_type == [NSDate class] ||
                      class_type == [NSSet class] ||
                      class_type == [NSValue class]){
                [self log:@"检测模型类异常数据类型"];
            }else{
                property_info = [[LL_PropertyInfo alloc] initWithType:_Model propertyName:property_name_string];
            }
            NSAssert(property_info == nil, @"property_info 为nil");
            [fields setObject:property_info forKey:property_name_string];
            
        }
    }
    free(propertys);
    return fields;
}

+ (LL_FieldType)parserFieldTypeWithAttribute:(NSString *)attribute
{
    NSArray *sub_attrs = [attribute componentsSeparatedByString:@","];
    NSString *first_sub_attr = sub_attrs.firstObject;
    first_sub_attr = [first_sub_attr substringToIndex:1];
    LL_FieldType field_type = _String;
    const char type = *[first_sub_attr UTF8String];
    switch (type) {
        case 'B':
            field_type = _Boolean;
            break;
        case 'C':
        case 'c':
            field_type = _Char;
            break;
        case 's':
        case 'S':
        case 'i':
        case 'I':
        case 'l':
        case 'L':
        case 'Q':
        case 'q':
            field_type = _Int;
            break;
        case 'f':
            field_type = _Float;
            break;
        case 'd':
        case 'D':
            field_type = _Double;
            break;
        default:
            break;
    }
    return field_type;
}
+ (BOOL)openTable:(Class)modelClass
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *cache_directory = [self databaseCacheDirectory];
    BOOL is_directory = YES;
    if (![fileManager fileExistsAtPath:cache_directory isDirectory:&is_directory]) {
        [fileManager createDirectoryAtPath:cache_directory withIntermediateDirectories:YES attributes:nil error:nil];
    }
    SEL VERSION = NSSelectorFromString(@"VERSION");
    NSString *version = @"1.0";
    if ([modelClass respondsToSelector:VERSION]) {
        IMP version_func = [modelClass methodForSelector:VERSION];
        NSString * (*func)(id, SEL) = (void *)version_func;
        version = func(modelClass, VERSION);
        NSString *local_model_name = [self localNameWithModel:modelClass];
        //Person_v1.0.0.sqlite
        if (local_model_name != nil && [local_model_name rangeOfString:version].location == NSNotFound) {
            //更新数据
            [self updateTableFieldWithModel:modelClass newVersion:version localModelName:local_model_name];
        }
    }
    NSString *database_cache_path = [NSString stringWithFormat:@"%@%@_v%@.sqlite",cache_directory,NSStringFromClass(modelClass),version];
    if (sqlite3_open(database_cache_path.UTF8String, &_ll_database) == SQLITE_OK) {
        return [self creatTable:modelClass];
    }
    return NO;
}

+ (BOOL)creatTable:(Class)modelClass
{
    NSString *table_name = NSStringFromClass(modelClass);
    NSDictionary *field_dictionary = [self parserModelObjectFieldsWithModelClass:modelClass];
    if (field_dictionary.count > 0) {
        NSString *create_table_sql = [NSString stringWithFormat:@"CREATE TABLE IF NOT EXISTS %@ (id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,",table_name];
        NSArray *field_array = field_dictionary.allKeys;
        for (NSString *field in field_array) {
            LL_PropertyInfo *property_info = field_dictionary[field];
            create_table_sql = [create_table_sql stringByAppendingFormat:@"%@ %@ DEFAULT",field,[self databaseFieldTypeWithType:property_info.type]];
            switch (property_info.type) {
                case _Data:
                case _String:
                case _Char:
                    create_table_sql = [create_table_sql stringByAppendingString:@"NULL,"];
                    break;
                case _Boolean:
                case _Int:
                case _Model:
                    create_table_sql = [create_table_sql stringByAppendingString:@"0,"];
                    break;
                case _Float:
                case _Double:
                case _Number:
                    create_table_sql = [create_table_sql stringByAppendingString:@"0.0,"];
                    break;
                default:
                    break;
            }
        }
        create_table_sql = [create_table_sql substringWithRange:NSMakeRange(0, create_table_sql.length - 1)];
        create_table_sql = [create_table_sql stringByAppendingString:@")"];
        return [self execSql:create_table_sql];
    }
    return NO;
}

+ (sqlite3_int64)getModelMaxIdWithClass:(Class)model_class
{
    sqlite3_int64 max_id = 0;
    if (_ll_database) {
        NSString *select_sql = [NSString stringWithFormat:@"SELECT MAX(id) AS MAXVALUE FROM %@",NSStringFromClass([model_class class])];
        sqlite3_stmt *pp_stmt;
        if (sqlite3_prepare_v2(_ll_database, select_sql.UTF8String, +1, &pp_stmt, NULL) == SQLITE_OK) {
            while (sqlite3_step(pp_stmt) == SQLITE_ROW) {
                max_id = sqlite3_column_int64(pp_stmt, 0);
            }
        }
        sqlite3_finalize(pp_stmt);
    }
    return max_id;
}
+ (NSArray *)getModelFieldNameWithClass:(Class)model_class
{
    NSMutableArray *field_name_array = [NSMutableArray array];
    if (_ll_database) {
        NSString *select_sql = [NSString stringWithFormat:@"SELECT * FROM %@ where id = %lld",NSStringFromClass([model_class class]),[self getModelMaxIdWithClass:model_class]];
        sqlite3_stmt *pp_stmt;
        if (sqlite3_prepare_v2(_ll_database, select_sql.UTF8String, -1, &pp_stmt, NULL) == SQLITE_OK) {
            int column_count = sqlite3_column_count(pp_stmt);
            for (int column = 0; column < column_count; column++) {
                NSString *field_name = [NSString stringWithCString:sqlite3_column_name(pp_stmt, column) encoding:NSUTF8StringEncoding];
                [field_name_array addObject:field_name];
            }
        }
        NSLog(@"field_name_array:%@",field_name_array);
        sqlite3_finalize(pp_stmt);
    }
    return field_name_array;
}

+ (NSDictionary *)scanCommonSubModel:(id)model isClass:(BOOL)isClass
{
    Class model_class = isClass ? model : [model class];
    NSMutableDictionary *sub_model_info = [NSMutableDictionary dictionary];
    unsigned int property_count = 0;
    objc_property_t *propertys = class_copyPropertyList(model_class, &property_count);
    for (int i = 0; i < property_count; i++) {
        objc_property_t property_t = propertys[i];
        const char * property_name = property_getName(property_t);
        const char * property_attributes = property_getAttributes(property_t);
        NSString *property_name_string = [NSString stringWithUTF8String:property_name];
        NSString *property_attributes_string = [NSString stringWithUTF8String:property_attributes];
        NSArray *property_attributes_list = [property_attributes_string componentsSeparatedByString:@"\""];
        if (property_attributes_list.count > 1) {
            Class class_type = NSClassFromString(property_attributes_list[1]);
            if (class_type != [NSString class] &&
                class_type != [NSArray class] &&
                class_type != [NSNumber class] &&
                class_type != [NSDictionary class] &&
                class_type != [NSData class] &&
                class_type != [NSDate class] &&
                class_type != [NSValue class] &&
                class_type != [NSSet class]) {
                if (isClass) {
                    [sub_model_info setObject:property_attributes_list[1] forKey:property_name_string];
                }else{
                    id sub_model = [model valueForKey:property_name_string];
                    if (sub_model) {
                        [sub_model_info setObject:sub_model forKey:property_name_string];
                    }
                }
            }
        }
    }
    free(propertys);
    return sub_model_info;
}

+ (NSDictionary *)scanSubModelClass:(Class)model_class
{
    return [self scanCommonSubModel:model_class isClass:YES];
}

+ (NSDictionary *)scanSubModelObject:(NSObject *)model_object
{
    return [self scanCommonSubModel:model_object isClass:NO];
}

+ (void)updateTableFieldWithModel:(Class)model_class
                       newVersion:(NSString *)newVersion
                   localModelName:(NSString *)local_model_name
{
    NSString *table_name = NSStringFromClass(model_class);
    NSString *cache_directory = [self databaseCacheDirectory];
    NSString *database_cache_path = [NSString stringWithFormat:@"%@%@",cache_directory,local_model_name];
    if (sqlite3_open(database_cache_path.UTF8String, &_ll_database) == SQLITE_OK) {
        NSArray *old_model_field_name_array = [self getModelFieldNameWithClass:model_class];
        //包含property_info对象字典
        NSDictionary *new_model_info = [self parserModelObjectFieldsWithModelClass:model_class];
        NSMutableString *delete_field_names = [NSMutableString string];
        NSMutableString *add_field_names = [NSMutableString string];
      
        [old_model_field_name_array enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            if (new_model_info[obj] == nil) {
                [delete_field_names appendString:obj];
                [delete_field_names appendString:@" ,"];
            }
        }];
        [new_model_info enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, LL_PropertyInfo *obj, BOOL * _Nonnull stop) {
            if (![old_model_field_name_array containsObject:key]) {
                [add_field_names appendFormat:@"%@ %@,",key,[self databaseFieldTypeWithType:obj.type]];
            }
        }];
        if (add_field_names.length > 0) {
            NSArray *add_field_name_array = [add_field_names componentsSeparatedByString:@","];
            [add_field_name_array enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                NSString *add_field_name_sql = [NSString stringWithFormat:@"ALTER TABLE %@ ADD %@",table_name,obj];
                [self execSql:add_field_name_sql];
            }];
        }
        if (delete_field_names.length > 0) {
            [delete_field_names deleteCharactersInRange:NSMakeRange(delete_field_names.length - 1, 1)];
            NSString *select_sql = [NSString stringWithFormat:@"SELECT * FROM %@",table_name];
            NSMutableArray *old_model_data_array = [NSMutableArray array];
            sqlite3_stmt *pp_stmt = nil;
            //扫描类是否包含其他类
            NSDictionary *sub_model_class_info = [self scanSubModelClass:model_class];
            NSMutableString *sub_model_name = [NSMutableString string];
            [sub_model_class_info enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
                [sub_model_name appendString:key];
                [sub_model_name appendString:@" "];
            }];
            if (sqlite3_prepare_v2(_ll_database, select_sql.UTF8String, -1, &pp_stmt, NULL) == SQLITE_OK) {
                int colum_count = sqlite3_column_count(pp_stmt);
                //操作每一行
                while (sqlite3_step(pp_stmt) == SQLITE_ROW) {
                    id new_model_object = [model_class new];
                    //每一行中的列model的值update
                    for (int i = 0; i < colum_count; i++) {
                        NSString *old_field_name = [NSString stringWithCString:sqlite3_column_name(pp_stmt, i) encoding:NSUTF8StringEncoding];
                        LL_PropertyInfo *property_info = new_model_info[old_field_name];
                        if (property_info == nil) continue;
                        switch (property_info.type) {
                            case _Number:
                            {
                                double value = sqlite3_column_double(pp_stmt, i);
                                [new_model_object setValue:@(value) forKey:old_field_name];
                            }break;
                            case _Model:
                            {
                                sqlite3_int64 value = sqlite3_column_int64(pp_stmt, i);
                                [new_model_object setValue:@(value) forKey:old_field_name];
                            }break;
                            case _Int:
                            {
                                sqlite3_int64 value = sqlite3_column_int64(pp_stmt, i);
                                if (sub_model_name != nil && sub_model_name.length > 0) {
                                    if ([sub_model_name rangeOfString:old_field_name].location == NSNotFound) {
                                        ((void (*)(id, SEL, int64_t))(void *) objc_msgSend)((id)new_model_object, property_info.setter, value);
                                    }else{
                                        [new_model_object setValue:@(value) forKey:old_field_name];
                                    }
                                }else{
                                    ((void (*)(id, SEL, int64_t))(void *) objc_msgSend)((id)new_model_object, property_info.setter, value);
                                }
                            }break;
                            case _String:
                            {
                                const unsigned char * text = sqlite3_column_text(pp_stmt, i);
                                if (text != NULL) {
                                    NSString *value = [NSString stringWithCString:(const char *)text encoding:NSUTF8StringEncoding];
                                    [new_model_object setValue:value forKey:old_field_name];
                                }else{
                                    [new_model_object setValue:@"" forKey:old_field_name];
                                }
                            }
                                break;
                            case _Data:
                            {
                                int length = sqlite3_column_bytes(pp_stmt, i);
                                const void *blob = sqlite3_column_blob(pp_stmt, i);
                                if (blob) {
                                    NSData *value = [NSData dataWithBytes:blob length:length];
                                    [new_model_object setValue:value forKey:old_field_name];
                                }else{
                                    [new_model_object setValue:[NSData data] forKey:old_field_name];
                                }
                            }
                                break;
                            case _Char:
                            case _Boolean:
                            {
                                int value = sqlite3_column_int(pp_stmt, i);
                                ((void (*)(id, SEL, int))(void *) objc_msgSend)((id)new_model_object, property_info.setter, value);
                            }
                                break;
                            case _Float:
                            case _Double:
                            {
                                double value = sqlite3_column_double(pp_stmt, i);
                                ((void (*)(id, SEL, float))(void *) objc_msgSend)((id)new_model_object, property_info.setter, value);
                            }break;
                            default:
                                break;
                        }
                    }
                    [old_model_data_array addObject:new_model_object];
                }
            }
            sqlite3_finalize(pp_stmt);
            [self close];
            
            NSFileManager *fileManager = [NSFileManager defaultManager];
            NSString *file_path = [self localPathWithModel:model_class];
            if (file_path) {
                [fileManager removeItemAtPath:file_path error:nil];
            }
            if ([self openTable:model_class]) {
                //数据事务操作
                [self execSql:@"BEIGIN"];
                [old_model_data_array enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                    //update老数据
                    [self commonInsert:obj index:_NO_HANDLE_KEY_ID];
                }];
                [self execSql:@"COMMIT"];
                [self close];
                return;
            }
        }
        [self close];
        NSString *new_database_cache_path = [NSString stringWithFormat:@"%@%@_v%@",cache_directory,table_name,newVersion];
        NSFileManager *fileManager = [NSFileManager defaultManager];
        [fileManager moveItemAtPath:database_cache_path toPath:new_database_cache_path error:nil];
    }
}

+ (void)commonInsert:(id)model_object index:(NSInteger)index
{
    sqlite3_stmt *pp_stmt = nil;
    NSDictionary *field_dictionary = [self parserModelObjectFieldsWithModelClass:[model_object class]];
    NSString *table_name = NSStringFromClass([model_object class]);
    //INSERT INTO table_name (列1, 列2,...) VALUES (值1, 值2,....)
    __block NSString *insert_sql = [NSString stringWithFormat:@"INSERT INTO %@ (",table_name];
    NSArray *field_array = field_dictionary.allKeys;
    NSMutableArray * value_array = [NSMutableArray array];
    NSMutableArray * insert_field_array = [NSMutableArray array];
    [field_array enumerateObjectsUsingBlock:^(NSString *  _Nonnull field, NSUInteger idx, BOOL * _Nonnull stop) {
        LL_PropertyInfo *property_info = field_dictionary[field];
        NSLog(@"common insert property_info:%@",property_info);
        [insert_field_array addObject:field];
        insert_sql = [insert_sql stringByAppendingFormat:@"%@,",field];
        id value = [model_object valueForKey:field];
        id subModelKeyId = [self shareInstance].sub_model_info[property_info.name];
        if ((value && subModelKeyId == nil) || index == _NO_HANDLE_KEY_ID) {
            [value_array addObject:value];
        }else{
            switch (property_info.type) {
                case _Data:
                {
                    [value_array addObject:[NSData data]];
                }break;
                case _String:
                {
                    [value_array addObject:@""];
                }break;
                case _Number:
                {
                    [value_array addObject:@(0.0)];
                }break;
                case _Model:
                {
                    if ([subModelKeyId isKindOfClass:[NSArray class]]) {
                        [value_array addObject:subModelKeyId[index]];
                    }else{
                        if (subModelKeyId) {
                            [value_array addObject:subModelKeyId];
                        }else{
                            [value_array addObject:@(_NO_HANDLE_KEY_ID)];
                        }
                    }
                }break;
                case _Int:
                {
                    id sub_model_main_key_object = [self shareInstance].sub_model_info[property_info.name];
                    if (sub_model_main_key_object != nil) {
                        if (index != -1) {
                            [value_array addObject:sub_model_main_key_object[index]];
                        }else{
                            [value_array addObject:sub_model_main_key_object];
                        }
                    }else{
                        NSNumber *value = @(((int64_t (*)(id, SEL))(void *)objc_msgSend)((id)model_object, property_info.getter));
                        [value_array addObject:value];
                    }
                }break;
                case _Boolean:
                {
                    NSNumber *value = @(((Boolean (*)(id, SEL))(void *)objc_msgSend)((id)model_object, property_info.getter));
                    [value_array addObject:value];
                }break;
                case _Char:
                {
                    NSNumber *value = @(((int8_t (*)(id, SEL))(void *)objc_msgSend)((id)model_object, property_info.getter));
                    [value_array addObject:value];
                }break;
                case _Double:
                {
                    NSNumber *value = @(((double (*)(id, SEL))(void *)objc_msgSend)((id)model_object, property_info.getter));
                    [value_array addObject:value];
                }break;
                case _Float:
                {
                    NSNumber *value = @(((float (*)(id, SEL))(void *)objc_msgSend)((id)model_object, property_info.getter));
                    [value_array addObject:value];
                }break;
                default:
                    break;
            }
        }
    }];
    //INSERT INTO table_name (列1, 列2,...) VALUES (值1, 值2,....)
    insert_sql = [insert_sql substringWithRange:NSMakeRange(0, insert_sql.length - 1)];
    insert_sql = [insert_sql stringByAppendingString:@") VALUES ("];
    [field_array enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        insert_sql = [insert_sql stringByAppendingString:@"?,"];
    }];
    insert_sql = [insert_sql substringWithRange:NSMakeRange(0, insert_sql.length - 2)];
    insert_sql = [insert_sql stringByAppendingString:@")"];
    
    if (sqlite3_prepare_v2(_ll_database, insert_sql.UTF8String, -1, &pp_stmt, NULL) == SQLITE_OK) {
        [field_array enumerateObjectsUsingBlock:^(NSString *  _Nonnull field, NSUInteger idx, BOOL * _Nonnull stop) {
            LL_PropertyInfo *property_info = field_dictionary[field];
            id value = value_array[idx];
            //key id = 0,按列从1开始赋值
            int index = (int)[insert_field_array indexOfObject:field] + 1;
            switch (property_info.type) {
                case _Data:
                {
                    sqlite3_bind_blob(pp_stmt, index, [value bytes], (int)[value length], SQLITE_TRANSIENT);
                }break;
                case _String:
                {
                    sqlite3_bind_text(pp_stmt, index, [value UTF8String], -1, SQLITE_TRANSIENT);
                }break;
                case _Number:
                {
                    sqlite3_bind_double(pp_stmt, index, [value doubleValue]);
                }break;
                case _Model:
                {
                    sqlite3_bind_int64(pp_stmt, index, (sqlite3_int64)[value integerValue]);
                }break;
                case _Int:
                {
                    sqlite3_bind_int64(pp_stmt, index, (sqlite3_int64)[value longLongValue]);
                }break;
                case _Boolean:
                {
                    sqlite3_bind_int(pp_stmt, index, [value boolValue]);
                }break;
                case _Char:
                {
                    sqlite3_bind_int(pp_stmt, index, [value intValue]);
                }break;
                case _Float:
                {
                    sqlite3_bind_double(pp_stmt, index, [value floatValue]);
                }break;
                case _Double:
                {
                    sqlite3_bind_double(pp_stmt, index, [value doubleValue]);
                }break;
                    
                default:
                    break;
            }
        }];
        if (sqlite3_step(pp_stmt) != SQLITE_DONE) {
            sqlite3_finalize(pp_stmt);
        }
    }else{
        [self log:@"Sorry存储数据失败,建议检查模型类属性类型是否符合规范"];
    }
}

+ (NSArray *)commonInsertSubArrayModelObject:(NSArray *)sub_array_model_object
{
    NSMutableArray *id_array = [NSMutableArray array];
    __block sqlite3_int64 _id = -1;
    Class first_sub_model_class = [sub_array_model_object.firstObject class];
    if (sub_array_model_object.count > 0 &&
        [self openTable:first_sub_model_class]) {
        _id = [self getModelMaxIdWithClass:first_sub_model_class];
        [self execSql:@"BEGIN"];
        [sub_array_model_object enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            _id++;
            [self commonInsert:obj index:idx];
            [id_array addObject:@(_id)];
        }];
        [self execSql:@"COMMIT"];
        [self close];
    }
    return id_array;
}

+ (NSArray *)insertSubModelArray:(NSArray *)model_array
{
    id first_model_object = model_array.firstObject;
    NSDictionary *sub_model_object_info = [self scanSubModelObject:first_model_object];
    if (sub_model_object_info.count > 0) {
        NSMutableDictionary *sub_model_object_info = [NSMutableDictionary dictionary];
        [model_array enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            NSDictionary *temp_sub_model_object_info = [self scanSubModelObject:obj];
            [temp_sub_model_object_info enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
                if (sub_model_object_info[key] != nil) {
                    NSMutableArray *temp_sub_array = [sub_model_object_info[key] mutableCopy];
                    [temp_sub_array addObject:obj];
                    sub_model_object_info[key] = temp_sub_array;
                }else{
                    NSMutableArray *temp_sub_array = [NSMutableArray array];
                    [temp_sub_array addObject:obj];
                    sub_model_object_info[key] = temp_sub_array;
                }
            }];
        }];
        if (sub_model_object_info.count > 0) {
            [sub_model_object_info enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, NSArray *subArray, BOOL * _Nonnull stop) {
                NSArray *sub_id_array = [self insertSubModelArray:subArray];
                [self shareInstance].sub_model_info[key] = sub_id_array;
            }];
        }
    }
    return [self commonInsertSubArrayModelObject:model_array];
}

+ (void)inserts:(NSArray *)model_array
{
    dispatch_semaphore_wait([self shareInstance].dsema, DISPATCH_TIME_FOREVER);
    @autoreleasepool {
        [[self shareInstance].sub_model_info removeAllObjects];
        if (model_array != nil && model_array.count > 0) {
            [self insertSubModelArray:model_array];
        }
    }
    dispatch_semaphore_signal([self shareInstance].dsema);
}

+ (sqlite_int64)commoninsertSubModelObject:(id)sub_model_object
{
    sqlite_int64 _id = -1;
    if ([self openTable:[sub_model_object class]]) {
        [self execSql:@"BEGIN"];
        [self commonInsert:sub_model_object index:-1];
        [self execSql:@"COMMIT"];
        _id = [self getModelMaxIdWithClass:[sub_model_object class]];
        [self close];
    }
    return _id;
}

+ (sqlite_int64)insertModelObject:(id)model_object
{
    NSDictionary *sub_model_objects_info = [self scanSubModelObject:model_object];
    if (sub_model_objects_info.count > 0) {
        [sub_model_objects_info enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
            sqlite_int64 _id = [self insertModelObject:obj];
            [[self shareInstance].sub_model_info setObject:@(_id) forKey:key];
        }];
    }
    return  [self commoninsertSubModelObject:model_object];
}

+ (void)insert:(id)model_object
{
    dispatch_semaphore_wait([self shareInstance].dsema, DISPATCH_TIME_FOREVER);
    @autoreleasepool {
        [[self shareInstance].sub_model_info removeAllObjects];
        [self insertModelObject:model_object];
    }
    dispatch_semaphore_signal([self shareInstance].dsema);

}

+ (NSArray *)commonQuery:(Class)model_class
              conditions:(NSArray *)conditions
            subModelName:(NSString *)sub_model_name
               queryType:(LL_QueryType)query_type
{
    if (![self openTable:model_class]) {
        return @[];
    }
    NSDictionary *field_dictionary = [self parserModelObjectFieldsWithModelClass:model_class];
    NSString *table_name = NSStringFromClass([model_class class]);
    NSString *select_sql = [NSString stringWithFormat:@"SELECT * FROM %@",table_name];
    NSString *where = nil;
    NSString *order = nil;
    NSString *limit = nil;
    if (conditions != nil && conditions.count > 0) {
        switch (query_type) {
            case _Where:
            {
                where = conditions.firstObject;
                if (where.length > 0) {
                    select_sql = [select_sql stringByAppendingFormat:@" WHERE %@",where];
                }
            }break;
            case _Order:
            {
                order = conditions.firstObject;
                if (order.length > 0) {
                    select_sql = [select_sql stringByAppendingFormat:@" ORDER %@",order];
                }
            }break;
            case _Limit:
            {
                limit = conditions.firstObject;
                if (limit.length > 0) {
                    select_sql = [select_sql stringByAppendingFormat:@" LIMIT %@",limit];
                }
            }break;
            case _WhereOrder:
            {
                if (conditions.count > 0) {
                    where = conditions.firstObject;
                    if (where.length > 0) {
                        select_sql = [select_sql stringByAppendingFormat:@" WHERE %@",where];
                    }
                }
                if (conditions.count > 1) {
                    order = conditions.lastObject;
                    if (order.length > 0) {
                        select_sql = [select_sql stringByAppendingFormat:@" ORDER %@",order];
                    }
                }
            }break;
            case _WhereLimit:
            {
                if (conditions.count > 0) {
                    where = conditions.firstObject;
                    if (where.length > 0) {
                        select_sql = [select_sql stringByAppendingFormat:@" WHERE %@",where];
                    }
                }
                if (conditions.count > 1) {
                    limit = conditions.lastObject;
                    if (limit.length > 0) {
                        select_sql = [select_sql stringByAppendingFormat:@" LIMIT %@",limit];
                    }
                }
            }break;
            case _OrderLimit:
            {
                if (conditions.count > 0) {
                    order = conditions.firstObject;
                    if (order.length > 0) {
                       select_sql = [select_sql stringByAppendingFormat:@" ORDER %@",order];
                    }
                }
                if (conditions.count > 1) {
                    limit = conditions.lastObject;
                    if (limit.length > 0) {
                        select_sql = [select_sql stringByAppendingFormat:@" LIMIT %@",limit];
                    }
                }
            }break;
            case _WhereOrderLimit:
            {
                if (conditions.count > 0) {
                    where = conditions.firstObject;
                    if (where.length > 0) {
                        select_sql = [select_sql stringByAppendingFormat:@" WHERE %@",where];
                    }
                }
                if (conditions.count > 1) {
                    order = conditions[1];
                    if (order.length > 0) {
                        select_sql = [select_sql stringByAppendingFormat:@" ORDER %@",order];
                    }
                }
                if (conditions.count > 2) {
                    limit = conditions.lastObject;
                    if (limit.length > 0) {
                        select_sql = [select_sql stringByAppendingFormat:@" LIMIT %@",limit];
                    }
                }
            }break;
            default:
                break;
        }
    }
    NSMutableArray *model_object_array = [NSMutableArray array];
    sqlite3_stmt *pp_stmt = nil;
    if (sqlite3_prepare_v2(_ll_database, [select_sql UTF8String], -1, &pp_stmt, NULL) == SQLITE_OK) {
        int column_count = sqlite3_column_count(pp_stmt);
        while (sqlite3_step(pp_stmt) == SQLITE_ROW) {
            id model_object = [model_class new];
            for (int column = 0; column < column_count; column++) {
                NSString *field_name = [NSString stringWithCString:sqlite3_column_name(pp_stmt, column) encoding:NSUTF8StringEncoding];
                LL_PropertyInfo *property_info = field_dictionary[field_name];
                if (property_info == nil ) continue;
                switch (property_info.type) {
                    case _Data:
                    {
                        int length = sqlite3_column_bytes(pp_stmt, column);
                        const void * blob = sqlite3_column_blob(pp_stmt, column);
                        if (blob != NULL) {
                            NSData *value = [NSData dataWithBytes:blob length:length];
                            [model_object setValue:value forKey:field_name];
                        }
                    }break;
                    case _String:
                    {
                        const unsigned char * text = sqlite3_column_text(pp_stmt, column);
                        if (text != NULL) {
                            NSString *value = [NSString stringWithCString:(const char *)text encoding:NSUTF8StringEncoding];
                            [model_object setValue:value forKey:field_name];
                        }
                    }break;
                    case _Number:
                    {
                        double value = sqlite3_column_double(pp_stmt, column);
                        [model_object setValue:@(value) forKey:field_name];
                    }break;
                    case _Model:
                    {
                        sqlite3_int64 value = sqlite3_column_int64(pp_stmt, column);
                        [model_object setValue:@(value) forKey:field_name];
                    }break;
                    case _Int:
                    {
                        sqlite3_int64 value = sqlite3_column_int64(pp_stmt, column);
                        if (sub_model_name != nil && sub_model_name.length > 0) {
                            if ([sub_model_name rangeOfString:field_name].location == NSNotFound) {
                                ((void (*)(id, SEL, int64_t))(void *) objc_msgSend)((id)model_object, property_info.setter, value);
                            }else{
                                [model_object setValue:@(value) forKey:field_name];
                            }
                        }else{
                            ((void (*)(id, SEL, int64_t))(void *) objc_msgSend)((id)model_object, property_info.setter, value);
                        }
                    }break;
                    case _Float: {
                        double value = sqlite3_column_double(pp_stmt, column);
                        ((void (*)(id, SEL, float))(void *) objc_msgSend)((id)model_object, property_info.setter, value);
                    }
                        break;
                    case _Double: {
                        double value = sqlite3_column_double(pp_stmt, column);
                        ((void (*)(id, SEL, double))(void *) objc_msgSend)((id)model_object, property_info.setter, value);
                    }
                        break;
                    case _Char: {
                        int value = sqlite3_column_int(pp_stmt, column);
                        ((void (*)(id, SEL, int))(void *) objc_msgSend)((id)model_object, property_info.setter, value);
                    }
                        break;
                    case _Boolean: {
                        int value = sqlite3_column_int(pp_stmt, column);
                        ((void (*)(id, SEL, int))(void *) objc_msgSend)((id)model_object, property_info.setter, value);
                    }
                        break;
                    default:
                        break;
                }
            }
            [model_object_array addObject:model_object];
        }
    }else{
        [self log:@"Sorry查询语句异常,建议检查查询条件Sql语句语法是否正确"];
    }
    sqlite3_finalize(pp_stmt);
    [self close];
    return model_object_array;
}


+ (NSString *)localNameWithModel:(Class)model_class
{
    return [self commonLocalPathWithModel:model_class isPath:NO];
}

+ (NSString *)localPathWithModel:(Class)model_class
{
    return [self commonLocalPathWithModel:model_class isPath:YES];
}

+ (NSString *)commonLocalPathWithModel:(Class)model_class isPath:(BOOL)isPath
{
    NSString *class_name = NSStringFromClass(model_class);
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *file_directory = [self databaseCacheDirectory];
    BOOL isDirectory = YES;
    __block NSString *file_path = nil;
    if ([fileManager fileExistsAtPath:file_directory isDirectory:&isDirectory]) {
        NSArray <NSString *>*file_name_array = [fileManager contentsOfDirectoryAtPath:file_directory error:nil];
        if (file_name_array.count > 0 && file_name_array != nil) {
            [file_name_array enumerateObjectsUsingBlock:^(NSString * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                if ([obj rangeOfString:class_name].location != NSNotFound) {
                    if (isPath) {
                        file_path = [NSString stringWithFormat:@"%@%@",file_directory,obj];
                    }else{
                        file_path = [obj mutableCopy];
                    }
                    *stop = YES;
                }
            }];
        }
    }
    return file_path;
}

+ (BOOL)execSql:(NSString *)sql
{
    return sqlite3_exec(_ll_database, [sql UTF8String], nil, nil, nil) == SQLITE_OK;
}

+ (void)close
{
    if (_ll_database) {
        sqlite3_close(_ll_database);
        _ll_database = nil;
    }
}
+ (NSString *)databaseFieldTypeWithType:(LL_FieldType)type
{
    switch (type) {
        case _String:
            return String_LL;
        case _Model:
            return Model_LL;
        case _Int:
            return Int_LL;
        case _Number:
        case _Double:
            return Double_LL;
        case _Float:
            return Float_LL;
        case _Char:
            return Char_LL;
        case _Boolean:
            return Boolean_LL;
        case _Data:
            return Data_LL;
        default:
            break;
    }
}
+ (void)log:(NSString *)msg {
    NSLog(@"LLModelSqlite:[%@]",msg);
}
@end
