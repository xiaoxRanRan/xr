// vim: set ts=4 sw=4 sts=4 et:
#if defined _l4d3_scoremod_DRDK_remake_included
 #endinput
#endif
#define _l4d3_scoremod_DRDK_remake_included

#pragma semicolon 1

/**
 * L4D2 ScoreMod Remake by Air - Include 文件
 *
 * 提供原生函数 (natives)，让其他插件可以查询由
 * l4d3_scoremod_DRDK_remake.smx 插件计算出的得分数据。
 *
 * 请确保主插件 (l4d3_scoremod_DRDK_remake.smx) 正在运行，
 * 并且已经取消了其 CreateNative 调用的注释。
 */

/**
 * 返回当前回合为生还者团队计算的伤害得分。
 * 这个值基于永久和临时生命值的损失，可能根据设置混合计算。
 *
 * @return      当前的伤害得分 (浮点数)。如果没有生还者到达终点或计算出的得分为负数，则返回 0.0。
 * @error       如果原生函数不可用（插件未运行或未注册 natives），则抛出错误。
 */
native float SMPlus_GetDamageBonus();

/**
 * 返回当前回合为生还者团队计算的物品得分。
 * 基于插件 CVar 的设置，考虑回合结束时存活生还者持有的药丸、肾上腺素、医疗包和投掷物。
 *
 * 注意：计算在主插件内部进行，通常在回合结束时。
 * 在回合中途调用可能无法反映最终的物品得分。
 *
 * @return      当前的物品得分 (浮点数)。
 * @error       如果原生函数不可用，则抛出错误。
 */
native float SMPlus_GetItemsBonus();

/**
 * 返回当前地图配置下可能获得的最大物品得分。
 * 这个值取决于每种物品配置的价值 (CVar) 和生还者团队规模 ('survivor_limit')。
 *
 * @return      可能的最大物品得分 (浮点数)。
 * @error       如果原生函数不可用，则抛出错误。
 */
native float SMPlus_GetItemsMaxBonus();

/**
 * 返回当前地图配置下可能获得的最大伤害得分。
 * 这是扣除任何生命值损失之前的基准值。它取决于地图距离、生还者倍数 CVar ('am_survivor_multi') 和团队规模。
 *
 * @return      可能的最大伤害得分 (浮点数)。
 * @error       如果原生函数不可用，则抛出错误。
 */
native float SMPlus_GetMaxDamageBonus();

/**
 * 返回当前回合为生还者团队计算的临时生命值额外奖励得分。
 * 这个奖励通常在团队到达安全室且在本回合没有损失任何临时生命值时授予。
 * 需要主插件中的 'am_bonus_allow_temp_extra' CVar 被启用。
 *
 * 注意：计算在主插件内部进行，通常在回合结束时。
 *
 * @return      当前的临时生命值额外奖励得分 (浮点数)。如果不适用、通过 CVar 禁用或损失了临时生命值，则返回 0.0。
 * @error       如果原生函数不可用，则抛出错误。
 */
native float SMPlus_GetTempExtraBonus();

/**
 * 返回当前地图配置下可能获得的最大临时生命值额外奖励得分。
 * 这个值取决于地图距离和 'am_temp_extra_bonus_factor' CVar。
 * 需要主插件中的 'am_bonus_allow_temp_extra' CVar 被启用。
 *
 * @return      可能的最大临时生命值额外奖励得分 (浮点数)。
 *              如果该功能通过 CVar 禁用，则返回 0.0。
 * @error       如果原生函数不可用，则抛出错误。
 */
native float SMPlus_GetTempExtraBonusWorth();

/**
 * 建议在调用原生函数之前检查它们是否可用，
 * 尽管如果调用了未注册的函数，SourceMod 通常会记录错误。
 *
 * 示例:
 * if (GetFeatureStatus(FeatureType_Native, "SMPlus_GetDamageBonus") == FeatureStatus_Available) {
 *     float damageBonus = SMPlus_GetDamageBonus();
 *     // ... 使用这个值
 * }
 */