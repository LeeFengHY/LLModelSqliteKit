//
//  LLModelSqlite.h
//  LLModelSqliteKit
//
//  Created by QFWangLP on 2017/2/13.
//  Copyright © 2017年 LeeFengHY. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface LLModelSqlite : NSObject


/**
 说明：存储模型数组到本地（事物方式）

 @param model_array 模型数组对象（model_array里对象类型和模型一致）
 */
+ (void)inserts:(NSArray *)model_array;

/**
 说明：存储模型到本地

 @param model_object 模型对象
 */
+ (void)insert:(id)model_object;

/**
 说明：查询本地模型对象

 @param model_class 模型类
 @return 模型对象数组
 */
+ (NSArray *)query:(Class)model_class;

/**
 说明：查询本地模型对象

 @param model_class 模型类
 @param where 查询条件（查询语法和SQL语法一样，where为空则查询所有）
 @return 模型对象数组
 */
+ (NSArray *)query:(Class)model_class where:(NSString *)where;

/**
 说明：查询本地模型对象

 @param model_class 模型类
 @param order 排序条件（排序语法和SQL order 查询语法一样，order为空则不排序）
 @return 模型对象数组
 */
+ (NSArray *)query:(Class)model_class order:(NSString *)order;

/**
 说明：查询本地模型对象

 @param model_class 模型类
 @param limit 限制条件（限制语法和SQL limit 查询语法一样，limit为空则不限制查询）
 @return 模型对象数组
 */
+ (NSArray *)query:(Class)model_class limit:(NSString *)limit;

/**
 说明：查询本地模型对象

 @param model_class 模型类
 @param where 查询条件（查询语法和SQL where 查询语法一样 where为空则查询所有）
 @param order 排序条件（排序语法和SQL order 查询语法一样，order为空则不排序）
 @return 模型对象数组
 */
+ (NSArray *)query:(Class)model_class where:(NSString *)where order:(NSString *)order;


/**
 说明：查询本地模型数组

 @param model_class 模型类
 @param where 查询条件（查询语法和SQL where 查询语法一样 where为空则查询所有）
 @param limit 限制条件（限制语法和SQL limit 查询语法一样，limit为空则不限制查询）
 @return 模型对象数组
 */
+ (NSArray *)query:(Class)model_class where:(NSString *)where limit:(NSString *)limit;

/**
 说明：查询本地模型

 @param model_class 模型类
 @param order 排序条件（排序语法和SQL order 查询语法一样，order为空则不排序）
 @param limit 限制条件（限制语法和SQL limit 查询语法一样，limit为空则不限制查询）
 @return 模型对象数组
 */
+ (NSArray *)query:(Class)model_class order:(NSString *)order limit:(NSString *)limit;

/**
 说明：查询本地模型对象

 @param model_class 模型类
 @param where 查询条件（查询语法和SQL where 查询语法一样 where为空则查询所有）
 @param order 排序条件（排序语法和SQL order 查询语法一样，order为空则不排序）
 @param limit 限制条件（限制语法和SQL limit 查询语法一样，limit为空则不限制查询）
 @return 模型对象数组
 */
+ (NSArray *)query:(Class)model_class where:(NSString *)where order:(NSString *)order limit:(NSString *)limit;

/**
 说明：更新本地模型对象

 @param model_object 模型类
 @param where 查询条件（查询和SQL where 查询语法一样，where为空则更新所有）
 */
+ (void)update:(id)model_object where:(NSString *)where;

/**
 说明：清空本地模型对象

 @param model_class 模型类
 */
+ (void)clear:(Class)model_class;

/**
 说明：删除本地模型对象

 @param model_class 模型类
 @param where 查询条件（查询语法和SQL where 查询语法一样，where为空则删除所有）
 */
+ (void)deleteModel:(Class)model_class where:(NSString *)where;


/**
 说明：清空本地所有模型数据库
 */
+ (void)removeAllModel;

/**
 说明：清空本地指定模型数据库

 @param model_class 模型类
 */
+ (void)removeModel:(Class)model_class;

/**
 说明：返回本地模型数据库路径

 @param model_class 模型类
 @return 路径
 */
+ (NSString *)localPathWithModel:(Class)model_class;

/**
 说明：返回本地模型数据库版本号

 @param model_class 模型类
 @return 版本号
 */
+ (NSString *)versionWithModel:(Class)model_class;
@end

