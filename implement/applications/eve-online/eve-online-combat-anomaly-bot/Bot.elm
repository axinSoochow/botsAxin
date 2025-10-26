{- EVE Online战斗异常空间机器人版本 2025-10-14

   该机器人使用探针扫描器查找战斗异常空间，并使用无人机和武器模块击杀敌人。

   ## 功能特性

   + 自动检测异常空间中是否有其他飞行员，如果有则切换到其他异常空间
   + 通过机器人设置筛选特定类型的异常空间
   + 通过机器人设置避开危险或过强的敌人
   + 记住观察到的异常空间属性，如其他飞行员或危险敌人，以指导未来的异常空间选择

   ## 游戏客户端设置

   尽管该机器人相当健壮，但它不如人类智能。例如，它的感知能力比我们有限，因此我们需要设置游戏以确保机器人能够看到它需要的一切。以下是EVE Online客户端的设置说明：

   + 将UI语言设置为英语
   + 离港，打开探针扫描器、概览窗口和无人机窗口
   + 在船舶UI中，排列模块：
     + 将战斗中使用的模块（用于激活目标）放在顶行
     + 通过取消选中`Display Passive Modules`复选框隐藏被动模块
   + 配置键盘键'W'使船舶执行环绕动作

   ## 配置设置

   所有设置都是可选的；只有在默认值不适合您的用例时才需要它们。

   + `anomaly-name` : 要选择的异常空间名称。多次使用此设置可选择多个名称。
   + `hide-when-neutral-in-local` : 设置为'yes'可使机器人在'本地'聊天中出现中立或敌对玩家时停靠在空间站或结构中。
   + `avoid-rat` : 要通过跃迁避开的敌人名称。输入名称时使用它在概览中显示的形式。多次使用此设置可选择多个名称。
   + `prioritize-rat` : 锁定目标时优先考虑的敌人名称。输入名称时使用它在概览中显示的形式。多次使用此设置可选择多个名称。
   + `activate-module-always` : 船舶模块提示文本，这些模块应始终处于活动状态。例如："shield hardener"（护盾硬化器）。
   + `anomaly-wait-time`: 到达异常空间后考虑其完成前的最短等待时间。如果您看到一些异常空间中敌人出现的时间晚于您到达网格的时间，请使用此设置。
   + `warp-to-anomaly-distance`: 默认为'Within 0 m'（0米范围内）
   + `deactivate-module-on-warp` : 跃迁时要停用的模块名称。输入名称时使用它在提示文本中显示的形式。多次使用此设置可选择多个模块。
   + `hide-location-name` : 要隐藏的位置名称。输入名称时使用它在'位置'窗口中显示的形式。

   使用多个设置时，请在文本输入字段中为每个设置开始一个新行。
   以下是完整设置字符串的示例：

   ```
   anomaly-name = Drone Patrol
   anomaly-name = Drone Horde
   hide-when-neutral-in-local = yes
   avoid-rat = Infested Carrier
   activate-module-always = shield hardener
   hide-location-name = Dock me here
   ```

   要了解有关异常空间机器人的更多信息，请参阅 <https://to.botlab.org/guide/app/eve-online-combat-anomaly-bot>

-}
{-
   catalog-tags:eve-online,anomaly,ratting
   authors-forum-usernames:viir
-}


module Bot exposing
    ( State
    , botMain
    )

import BotLab.BotInterface_To_Host_2024_10_19 as InterfaceToHost
import Common
import Common.Basics exposing (listElementAtWrappedIndex, resultFirstSuccessOrFirstError, stringContainsIgnoringCase)
import Common.DecisionPath exposing (describeBranch)
import Common.EffectOnWindow as EffectOnWindow exposing (MouseButton(..))
import Common.PromptParser as PromptParser exposing (IntervalInt)
import Dict
import EveOnline.BotFramework
    exposing
        ( ModuleButtonTooltipMemory
        , OverviewWindowsMemory
        , ReadingFromGameClient
        , ShipModulesMemory
        , UseContextMenuCascadeNode(..)
        , localChatWindowFromUserInterface
        , menuCascadeCompleted
        , mouseClickOnUIElement
        , shipUIIndicatesShipIsWarpingOrJumping
        , uiNodeVisibleRegionLargeEnoughForClicking
        , useMenuEntryInLastContextMenuInCascade
        , useMenuEntryWithTextContaining
        , useMenuEntryWithTextContainingFirstOf
        , useMenuEntryWithTextContainingFirstOfCommonContinuation
        , useMenuEntryWithTextEqual
        )
import EveOnline.BotFrameworkSeparatingMemory
    exposing
        ( DecisionPathNode
        , UpdateMemoryContext
        , askForHelpToGetUnstuck
        , branchDependingOnDockedOrInSpace
        , clickModuleButtonButWaitIfClickedInPreviousStep
        , decideActionForCurrentStep
        , ensureInfoPanelLocationInfoIsExpanded
        , ensureOverviewsSorted
        , useContextMenuCascade
        , useContextMenuCascadeOnListSurroundingsButton
        , useContextMenuCascadeOnOverviewEntry
        , waitForProgressInGame
        )
import EveOnline.ParseUserInterface
    exposing
        ( OverviewWindowEntry
        , ShipUI
        , ShipUIModuleButton
        )
import EveOnline.UnstuckBot
import List.Extra
import Result.Extra
import Set


-- 默认机器人设置
defaultBotSettings : BotSettings
defaultBotSettings =
    { hideWhenNeutralInLocal = PromptParser.No -- 本地频道中有中立玩家时是否隐藏
    , anomalyNames = [] -- 要选择的异常空间名称列表
    , avoidRats = [] -- 要避开的敌人名称列表
    , prioritizeRats = [] -- 优先攻击的敌人名称列表
    , activateModulesAlways = [] -- 始终激活的模块名称列表
    , maxTargetCount = 5 -- 最大目标锁定数量
    , botStepDelayMilliseconds = { minimum = 1200, maximum = 1500 } -- 机器人步骤延迟（毫秒）
    , anomalyWaitTimeSeconds = 15 -- 在异常空间中的最短等待时间
    , orbitInCombat = PromptParser.Yes -- 战斗中是否环绕飞行
    , orbitObjectNames = [] -- 要环绕的物体名称列表
    , warpToAnomalyDistance = "Within 0 m" -- 跃迁到异常空间的距离
    , sortOverviewBy = Nothing -- 概览排序列
    , deactivateModuleOnWarp = [] -- 跃迁时停用的模块列表
    , hideLocationNames = [] -- 隐藏位置名称列表
    }


-- 解析机器人设置字符串
parseBotSettings : String -> Result String BotSettings
parseBotSettings =
    PromptParser.parseSimpleListOfAssignmentsSeparatedByNewlines
        ([ ( "hide-when-neutral-in-local"
           , { alternativeNames = []
             , description = "Set this to 'yes' to make the bot dock in a station or structure when a neutral or hostile appears in the 'local' chat."
             , valueParser =
                PromptParser.valueTypeYesOrNo
                    (\hide settings -> { settings | hideWhenNeutralInLocal = hide })
             }
           )
         , ( "anomaly-name"
           , { alternativeNames = []
             , description = "Name of anomalies to select. Use this setting multiple times to select multiple names."
             , valueParser =
                PromptParser.valueTypeString
                    (\anomalyName settings ->
                        { settings | anomalyNames = String.trim anomalyName :: settings.anomalyNames }
                    )
             }
           )
         , ( "avoid-rat"
           , { alternativeNames = []
             , description = "Name of a rat to avoid by warping away. Enter the name as it appears in the overview. Use this setting multiple times to select multiple names."
             , valueParser =
                PromptParser.valueTypeString
                    (\ratToAvoid settings ->
                        { settings | avoidRats = String.trim ratToAvoid :: settings.avoidRats }
                    )
             }
           )
         , ( "prioritize-rat"
           , { alternativeNames = [ "prio-rat", "priority-rat" ]
             , description = "Name of a rat to prioritize when locking targets. Enter the name as it appears in the overview. Use this setting multiple times to select multiple names."
             , valueParser =
                PromptParser.valueTypeString
                    (\ratToPrioritize settings ->
                        { settings | prioritizeRats = String.trim ratToPrioritize :: settings.prioritizeRats }
                    )
             }
           )
         , ( "activate-module-always"
           , { alternativeNames = []
             , description = "Text found in tooltips of ship modules that should always be active. For example: 'shield hardener'."
             , valueParser =
                PromptParser.valueTypeString
                    (\moduleName settings ->
                        { settings | activateModulesAlways = moduleName :: settings.activateModulesAlways }
                    )
             }
           )
         , ( "anomaly-wait-time"
           , { alternativeNames = []
             , description = "Minimum time to wait after arriving in an anomaly before considering it finished. Use this if you see anomalies in which rats arrive later than you arrive on grid."
             , valueParser =
                PromptParser.valueTypeInteger
                    (\anomalyWaitTimeSeconds settings ->
                        { settings | anomalyWaitTimeSeconds = anomalyWaitTimeSeconds }
                    )
             }
           )
         , ( "orbit-in-combat"
           , { alternativeNames = []
             , description = "Whether to keep the ship orbiting during combat"
             , valueParser =
                PromptParser.valueTypeYesOrNo
                    (\orbitInCombat settings ->
                        { settings | orbitInCombat = orbitInCombat }
                    )
             }
           )
         , ( "warp-to-anomaly-distance"
           , { alternativeNames = []
             , description = "Defaults to 'Within 0 m'"
             , valueParser =
                PromptParser.valueTypeString
                    (\warpToAnomalyDistance settings ->
                        { settings | warpToAnomalyDistance = warpToAnomalyDistance }
                    )
             }
           )
         , ( "sort-overview-by"
           , { alternativeNames = []
             , description = "Name of the overview column to use for sorting. For example: 'distance' or 'size'"
             , valueParser =
                PromptParser.valueTypeString
                    (\columnName settings ->
                        { settings | sortOverviewBy = Just columnName }
                    )
             }
           )
         , ( "bot-step-delay"
           , { alternativeNames = [ "step-delay" ]
             , description = "Minimum time between starting bot steps in milliseconds. You can also specify a range like `1000 - 2000`. The bot then picks a random value in this range."
             , valueParser =
                PromptParser.parseIntervalIntFromPointOrIntervalString
                    >> Result.map
                        (\delay settings -> { settings | botStepDelayMilliseconds = delay })
             }
           )
         , ( "orbit-object-name"
           , { alternativeNames = []
             , description = "Choose the name of large collidable objects to orbit. You can use this setting multiple times to select multiple objects."
             , valueParser =
                PromptParser.valueTypeString
                    (\orbitObjectName settings ->
                        { settings
                            | orbitObjectNames = String.trim orbitObjectName :: settings.orbitObjectNames
                            , orbitInCombat = PromptParser.Yes
                        }
                    )
             }
           )
         , ( "deactivate-module-on-warp"
           , { alternativeNames = []
             , description = "Name of a module to deactivate when warping. Enter the name as it appears in the tooltip. Use this setting multiple times to select multiple modules."
             , valueParser =
                PromptParser.valueTypeString
                    (\moduleName settings ->
                        { settings | deactivateModuleOnWarp = moduleName :: settings.deactivateModuleOnWarp }
                    )
             }
           )
         , ( "hide-location-name"
           , { alternativeNames = []
             , description = "Name of a location to hide. Enter the name as it appears in the 'Locations' window."
             , valueParser =
                PromptParser.valueTypeString
                    (\locationName settings ->
                        { settings
                            | hideLocationNames = String.trim locationName :: settings.hideLocationNames
                        }
                    )
             }
           )
         ]
            |> Dict.fromList
        )
        defaultBotSettings


-- 良好声望模式列表，用于识别本地频道中的友好玩家
goodStandingPatterns : List String
goodStandingPatterns =
    [ "good standing", "excellent standing", "is in your" ]


-- 机器人设置类型定义
type alias BotSettings =
    { hideWhenNeutralInLocal : PromptParser.YesOrNo -- 本地频道中有中立玩家时是否隐藏
    , anomalyNames : List String -- 要选择的异常空间名称列表
    , avoidRats : List String -- 要避开的敌人名称列表
    , prioritizeRats : List String -- 优先攻击的敌人名称列表
    , activateModulesAlways : List String -- 始终激活的模块名称列表
    , maxTargetCount : Int -- 最大目标锁定数量
    , anomalyWaitTimeSeconds : Int -- 在异常空间中的最短等待时间
    , botStepDelayMilliseconds : IntervalInt -- 机器人步骤延迟（毫秒）
    , orbitInCombat : PromptParser.YesOrNo -- 战斗中是否环绕飞行
    , orbitObjectNames : List String -- 要环绕的物体名称列表
    , warpToAnomalyDistance : String -- 跃迁到异常空间的距离
    , sortOverviewBy : Maybe String -- 概览排序列
    , deactivateModuleOnWarp : List String -- 跃迁时停用的模块列表
    , hideLocationNames : List String -- 隐藏位置名称列表
    }


-- 机器人状态类型
type alias State =
    EveOnline.UnstuckBot.UnstuckBotState
        (EveOnline.BotFrameworkSeparatingMemory.StateIncludingFramework BotSettings BotMemory)


-- 机器人内存类型，存储机器人运行时的各种状态信息
type alias BotMemory =
    { lastDockedStationNameFromInfoPanel : Maybe String -- 上次停靠的空间站名称
    , shipModules : ShipModulesMemory -- 船舶模块状态记忆
    , overviewWindows : OverviewWindowsMemory -- 概览窗口状态记忆
    , shipWarpingInLastReading : Maybe Bool -- 上次读取时船舶是否正在跃迁
    , visitedAnomalies : Dict.Dict String MemoryOfAnomaly -- 已访问的异常空间信息
    , notEnoughBandwidthToLaunchDrone : Bool -- 是否无人机带宽不足
    , droneBandwidthLimitatatinEvents : List { timeMilliseconds : Int, dronesInSpaceCount : Int } -- 无人机带宽限制事件记录
    }


-- 异常空间记忆类型，存储关于已访问异常空间的详细信息
type alias MemoryOfAnomaly =
    { arrivalTime : { milliseconds : Int } -- 到达时间
    , otherPilotsFoundOnArrival : List String -- 到达时发现的其他飞行员
    , ratsSeen : Set.Set String -- 在异常空间中看到的敌人名称集合
    }


-- 机器人决策上下文类型
type alias BotDecisionContext =
    EveOnline.BotFrameworkSeparatingMemory.StepDecisionContext BotSettings BotMemory


-- 忽略探针扫描结果的原因类型
type ReasonToIgnoreProbeScanResult
    = ScanResultHasNoID -- 扫描结果没有ID
    | AvoidAnomaly ReasonToAvoidAnomaly -- 因特定原因避开异常空间


-- 避开异常空间的具体原因类型
type ReasonToAvoidAnomaly
    = IsNoCombatAnomaly -- 不是战斗异常空间
    | DoesNotMatchAnomalyNameFromSettings -- 不匹配设置中的异常空间名称
    | FoundOtherPilotOnArrival String -- 到达时发现其他飞行员
    | FoundRatToAvoid String -- 发现要避开的敌人


-- 按攻击优先级分组的敌人类型
type alias RatsByAttackPriority =
    { overviewEntriesByPrio : List ( OverviewWindowEntry, List OverviewWindowEntry ) -- 按优先级分组的概览条目
    , targetsByPrio : List ( EveOnline.ParseUserInterface.Target, List EveOnline.ParseUserInterface.Target ) -- 按优先级分组的目标
    }


-- 描述避开异常空间的原因
describeReasonToAvoidAnomaly : ReasonToAvoidAnomaly -> String
describeReasonToAvoidAnomaly reason =
    case reason of
        IsNoCombatAnomaly ->
            "不是战斗异常空间"

        DoesNotMatchAnomalyNameFromSettings ->
            "不匹配设置中的异常空间名称"

        FoundOtherPilotOnArrival otherPilot ->
            "到达时发现其他飞行员: " ++ otherPilot

        FoundRatToAvoid rat ->
            "发现要避开的敌人: " ++ rat


-- 查找忽略探针扫描结果的原因
findReasonToIgnoreProbeScanResult : BotDecisionContext -> EveOnline.ParseUserInterface.ProbeScanResult -> Maybe ReasonToIgnoreProbeScanResult
findReasonToIgnoreProbeScanResult context probeScanResult =
    case probeScanResult.cellsTexts |> Dict.get "ID" of
        Nothing ->
            Just ScanResultHasNoID

        Just scanResultID ->
            let
                -- 判断是否为战斗异常空间
                isCombatAnomaly =
                    probeScanResult.cellsTexts
                        |> Dict.get "Group"
                        |> Maybe.map (stringContainsIgnoringCase "combat")
                        |> Maybe.withDefault False

                -- 判断是否匹配设置中的异常空间名称
                matchesAnomalyNameFromSettings =
                    (context.eventContext.botSettings.anomalyNames |> List.isEmpty)
                        || (context.eventContext.botSettings.anomalyNames
                                |> List.any
                                    (\anomalyName ->
                                        probeScanResult.cellsTexts
                                            |> Dict.get "Name"
                                            |> Maybe.map (String.toLower >> (==) (anomalyName |> String.toLower |> String.trim))
                                            |> Maybe.withDefault False
                                    )
                           )
            in
            if not isCombatAnomaly then
                Just (AvoidAnomaly IsNoCombatAnomaly)

            else if not matchesAnomalyNameFromSettings then
                Just (AvoidAnomaly DoesNotMatchAnomalyNameFromSettings)

            else
                -- 从记忆中查找是否有避开该异常空间的原因
                findReasonToAvoidAnomalyFromMemory context { anomalyID = scanResultID }
                    |> Maybe.map AvoidAnomaly


-- 从记忆中查找避开异常空间的原因
findReasonToAvoidAnomalyFromMemory : BotDecisionContext -> { anomalyID : String } -> Maybe ReasonToAvoidAnomaly
findReasonToAvoidAnomalyFromMemory context { anomalyID } =
    case memoryOfAnomalyWithID anomalyID context.memory of
        Nothing ->
            Nothing

        Just memoryOfAnomaly ->
            case memoryOfAnomaly.otherPilotsFoundOnArrival of
                otherPilotFoundOnArrival :: _ ->
                    -- 如果到达时发现其他飞行员，避开该异常空间
                    Just (FoundOtherPilotOnArrival otherPilotFoundOnArrival)

                [] ->
                    let
                        -- 查找在异常空间中看到的需要避开的敌人
                        ratsToAvoidSeen =
                            getRatsToAvoidSeenInAnomaly context.eventContext.botSettings memoryOfAnomaly
                    in
                    case ratsToAvoidSeen |> Set.toList of
                        ratToAvoid :: _ ->
                            -- 如果发现需要避开的敌人，避开该异常空间
                            Just (FoundRatToAvoid ratToAvoid)

                        [] ->
                            Nothing


-- 获取在异常空间中看到的需要避开的敌人
getRatsToAvoidSeenInAnomaly : BotSettings -> MemoryOfAnomaly -> Set.Set String
getRatsToAvoidSeenInAnomaly settings =
    .ratsSeen >> Set.filter (shouldAvoidRatAccordingToSettings settings)


-- 根据设置判断是否应该避开特定敌人
shouldAvoidRatAccordingToSettings : BotSettings -> String -> Bool
shouldAvoidRatAccordingToSettings settings ratName =
    settings.avoidRats |> List.map String.toLower |> List.member (ratName |> String.toLower)


-- 通过ID获取异常空间记忆
memoryOfAnomalyWithID : String -> BotMemory -> Maybe MemoryOfAnomaly
memoryOfAnomalyWithID anomalyID =
    .visitedAnomalies >> Dict.get anomalyID


-- 机器人决策根节点
anomalyBotDecisionRoot : BotDecisionContext -> DecisionPathNode
anomalyBotDecisionRoot context =
    anomalyBotDecisionRootBeforeApplyingSettings context
        |> EveOnline.BotFrameworkSeparatingMemory.setMillisecondsToNextReadingFromGameBase
            (randomIntFromInterval context context.eventContext.botSettings.botStepDelayMilliseconds)


-- 应用设置前的机器人决策根节点
anomalyBotDecisionRootBeforeApplyingSettings : BotDecisionContext -> DecisionPathNode
anomalyBotDecisionRootBeforeApplyingSettings context =
    generalSetupInUserInterface context
        |> Maybe.withDefault
            (branchDependingOnDockedOrInSpace
                { ifDocked =
                    case
                        continueIfShouldHide
                            { ifShouldHide =
                                describeBranch "Stay docked." waitForProgressInGame
                            }
                            context
                    of
                        Just stayDocked ->
                            stayDocked

                        Nothing ->
                            undockUsingStationWindow context
                                { ifCannotReachButton =
                                    describeBranch "No alternative for undocking" askForHelpToGetUnstuck
                                }
                , ifSeeShipUI =
                    decideNextActionWhenInSpace context
                }
                context.readingFromGameClient
            )


-- 用户界面通用设置函数，执行一系列UI准备工作
generalSetupInUserInterface : BotDecisionContext -> Maybe DecisionPathNode
generalSetupInUserInterface context =
    [ closeMessageBox
    , ensureInfoPanelLocationInfoIsExpanded
    , case context.eventContext.botSettings.sortOverviewBy of
        Nothing ->
            always Nothing

        Just sortOverviewBy ->
            ensureOverviewsSorted
                { sortColumnName = sortOverviewBy, skipSortingWhenNotScrollable = False }
                context.memory.overviewWindows
                >> List.filterMap
                    (\( _, ( description, maybeAction ) ) ->
                        maybeAction |> Maybe.map (describeBranch description)
                    )
                >> List.head
    ]
        |> List.filterMap ((|>) context.readingFromGameClient)
        |> List.head


-- 关闭消息框函数
closeMessageBox : ReadingFromGameClient -> Maybe DecisionPathNode
closeMessageBox readingFromGameClient =
    readingFromGameClient.messageBoxes
        |> List.head
        |> Maybe.map
            (\messageBox ->
                describeBranch "I see a message box to close."
                    (let
                        buttonCanBeUsedToClose button =
                            case button.mainText of
                                Nothing ->
                                    False

                                Just buttonText ->
                                    let
                                        buttonTextLower =
                                            String.toLower buttonText
                                    in
                                    List.member buttonTextLower [ "close", "ok" ]
                     in
                     case List.filter buttonCanBeUsedToClose messageBox.buttons of
                        [] ->
                            describeBranch "I see no way to close this message box." askForHelpToGetUnstuck

                        buttonToUse :: _ ->
                            describeBranch
                                ("Click on button '" ++ (buttonToUse.mainText |> Maybe.withDefault "") ++ "'.")
                                (case mouseClickOnUIElement MouseButtonLeft buttonToUse.uiNode of
                                    Err _ ->
                                        describeBranch "Failed to click" askForHelpToGetUnstuck

                                    Ok clickAction ->
                                        decideActionForCurrentStep clickAction
                                )
                    )
            )


-- 根据条件决定是否继续执行隐藏行为（如停靠）
continueIfShouldHide : { ifShouldHide : DecisionPathNode } -> BotDecisionContext -> Maybe DecisionPathNode
continueIfShouldHide config context =
    case checkIfShouldHide context of
        Nothing ->
            Nothing

        Just ( reason, justAskForHelp ) ->
            Just
                (describeBranch
                    reason
                    (if justAskForHelp then
                        askForHelpToGetUnstuck

                     else
                        config.ifShouldHide
                    )
                )


-- 检查是否应该隐藏（如停靠）的条件
checkIfShouldHide : BotDecisionContext -> Maybe ( String, Bool )
checkIfShouldHide context =
    let
        -- 检查是否没有船舶模块按钮
        hasNoShipModules : Bool
        hasNoShipModules =
            case context.readingFromGameClient.shipUI of
                Nothing ->
                    False

                Just shipUI ->
                    shipUI.moduleButtons == []
    in
    if hasNoShipModules then
        Just
            ( "船舶UI中没有模块按钮。"
            , False
            )

    else
        -- 检查会话结束时间，如果少于200秒则需要隐藏
        case
            context.eventContext
                |> EveOnline.BotFramework.secondsToSessionEnd
                |> Maybe.andThen (nothingFromIntIfGreaterThan 200)
        of
            Just secondsToSessionEnd ->
                Just
                    ( "会话将在 " ++ String.fromInt secondsToSessionEnd ++ " 秒后结束。"
                    , False
                    )

            Nothing ->
                -- 检查是否启用了本地频道中有中立玩家时隐藏的设置
                if context.eventContext.botSettings.hideWhenNeutralInLocal /= PromptParser.Yes then
                    Nothing

                else
                    case context.readingFromGameClient |> localChatWindowFromUserInterface of
                        Nothing ->
                            Just
                                ( "看不到本地聊天窗口。"
                                , True
                                )

                        Just localChatWindow ->
                            let
                                -- 判断聊天用户是否有良好声望
                                chatUserHasGoodStanding chatUser =
                                    goodStandingPatterns
                                        |> List.any
                                            (\goodStandingPattern ->
                                                case chatUser.standingIconHint of
                                                    Nothing ->
                                                        False

                                                    Just standingIconHint ->
                                                        stringContainsIgnoringCase
                                                            goodStandingPattern
                                                            standingIconHint
                                            )

                                -- 获取没有良好声望的用户列表（敌人或中立）
                                subsetOfUsersWithNoGoodStanding : List { uiNode : EveOnline.ParseUserInterface.UITreeNodeWithDisplayRegion, name : Maybe String, standingIconHint : Maybe String }
                                subsetOfUsersWithNoGoodStanding =
                                    case localChatWindow.userlist of
                                        Nothing ->
                                            []

                                        Just userlist ->
                                            userlist.visibleUsers
                                                |> List.filter (chatUserHasGoodStanding >> not)
                            in
                            if 1 < List.length subsetOfUsersWithNoGoodStanding then
                                Just
                                    ( "There is an enemy or neutral in local chat."
                                    , False
                                    )

                            else
                                Nothing


-- 逃跑函数：当需要隐藏时，机器人会前往指定位置或随机空间站
runAway : BotDecisionContext -> EveOnline.ParseUserInterface.ShipUI -> DecisionPathNode
runAway context shipUI =
    case context.eventContext.botSettings.hideLocationNames of
        [] ->
            -- 如果没有配置隐藏位置，停靠到随机空间站或结构
            dockAtRandomStationOrStructure context shipUI

        hideLocationNames ->
            -- 尝试前往配置的隐藏位置
            let
                routesToHideLocation =
                    dockOrWarpToLocationWithMatchingName
                        { namesFromSettingOrInfoPanel = hideLocationNames }
                        context
            in
            case routesToHideLocation.viaLocationsWindow of
                Just viaLocationsWindow ->
                    -- 通过位置窗口前往隐藏位置
                    viaLocationsWindow

                Nothing ->
                    case routesToHideLocation.viaOverview of
                        Just viaOverview ->
                            -- 通过概览前往隐藏位置
                            viaOverview

                        Nothing ->
                            -- 如果找不到配置的隐藏位置，使用太阳系菜单
                            describeBranch
                                (String.concat
                                    [ "在位置窗口或概览窗口中未找到配置的 "
                                    , String.fromInt (List.length hideLocationNames)
                                    , " 个位置中的任何一个 ("
                                    , String.join ", " hideLocationNames
                                    , ")。默认使用太阳系菜单。"
                                    ]
                                )
                                (routesToHideLocation.viaSolarSystemMenu ())


dockOrWarpToLocationWithMatchingName :
    { namesFromSettingOrInfoPanel : List String }
    -> BotDecisionContext
    ->
        { viaLocationsWindow : Maybe DecisionPathNode
        , viaOverview : Maybe DecisionPathNode
        , viaSolarSystemMenu : () -> DecisionPathNode
        }
dockOrWarpToLocationWithMatchingName { namesFromSettingOrInfoPanel } context =
    {-
       session-2025-04-29T00-59:
       A location given with settings is in space and is NOT directly at a structure.
       In the context menu for that location, we see following entries at the top:
       ----
       Warp to Within (0 m) -> This one appears to be expandable.
       Align to
       Show Info
       ...
    -}
    let
        destNamesSimplified : List String
        destNamesSimplified =
            List.map
                simplifyStationOrStructureNameFromSettingsBeforeComparingToMenuEntry
                namesFromSettingOrInfoPanel

        {-
           2023-01-11 Observation by Dean: Text in surroundings context menu entry sometimes wraps station name in XML tags:
           <color=#FF58A7BF>Niyabainen IV - M1 - Caldari Navy Assembly Plant</color>
        -}
        displayTextRepresentsMatchingStation : String -> Bool
        displayTextRepresentsMatchingStation displayName =
            let
                displayNameSimplified =
                    simplifyStationOrStructureNameFromSettingsBeforeComparingToMenuEntry
                        displayName
            in
            List.any
                (\destName ->
                    String.contains destName displayNameSimplified
                )
                destNamesSimplified
    in
    useContextMenuOnLocationWithMatchingName
        displayTextRepresentsMatchingStation
        (useMenuEntryWithTextContainingFirstOf
            [ ( "dock"
              , menuCascadeCompleted
              )
            , ( "Warp to Within (0 m)"
              , menuCascadeCompleted
              )
            , ( "Warp to"
              , useMenuEntryWithTextContaining "Within 0 m" menuCascadeCompleted
              )
            ]
        )
        context


useContextMenuOnLocationWithMatchingName :
    (String -> Bool)
    -> EveOnline.BotFramework.UseContextMenuCascadeNode
    -> BotDecisionContext
    ->
        { viaLocationsWindow : Maybe DecisionPathNode
        , viaOverview : Maybe DecisionPathNode
        , viaSolarSystemMenu : () -> DecisionPathNode
        }
useContextMenuOnLocationWithMatchingName nameMatches useMenu context =
    let
        viaLocationsWindow : Maybe DecisionPathNode
        viaLocationsWindow =
            case context.readingFromGameClient.locationsWindow of
                Nothing ->
                    Nothing

                Just locationsWindow ->
                    case
                        locationsWindow.placeEntries
                            |> List.filter (.mainText >> nameMatches)
                            |> List.head
                    of
                        Nothing ->
                            Nothing

                        Just placeEntry ->
                            Just
                                (EveOnline.BotFrameworkSeparatingMemory.useContextMenuCascade
                                    ( placeEntry.mainText, placeEntry.uiNode )
                                    useMenu
                                    context
                                )

        matchingOverviewEntry : Maybe OverviewWindowEntry
        matchingOverviewEntry =
            context.readingFromGameClient.overviewWindows
                |> List.concatMap .entries
                |> List.filter
                    (.objectName
                        >> Maybe.map nameMatches
                        >> Maybe.withDefault False
                    )
                |> List.head

        viaOverview =
            case matchingOverviewEntry of
                Just overviewEntry ->
                    Just
                        (EveOnline.BotFrameworkSeparatingMemory.useContextMenuCascadeOnOverviewEntry
                            useMenu
                            overviewEntry
                            context
                        )

                Nothing ->
                    Nothing
    in
    { viaLocationsWindow = viaLocationsWindow
    , viaOverview = viaOverview
    , viaSolarSystemMenu =
        \() ->
            let
                overviewWindowScrollControls =
                    context.readingFromGameClient.overviewWindows
                        |> List.filterMap .scrollControls
                        |> List.head
            in
            overviewWindowScrollControls
                |> Maybe.andThen scrollDown
                |> Maybe.withDefault
                    (useContextMenuCascadeOnListSurroundingsButton
                        (useMenuEntryWithTextContainingFirstOfCommonContinuation
                            [ "locations" ]
                            (useMenuEntryInLastContextMenuInCascade
                                { describeChoice = "select using the configured predicate"
                                , chooseEntry =
                                    List.filter (.text >> nameMatches)
                                        >> List.head
                                }
                                useMenu
                            )
                        )
                        context
                    )
    }


scrollDown : EveOnline.ParseUserInterface.ScrollControls -> Maybe DecisionPathNode
scrollDown scrollControls =
    case scrollControls.scrollHandle of
        Nothing ->
            Nothing

        Just scrollHandle ->
            let
                scrollControlsTotalDisplayRegion =
                    scrollControls.uiNode.totalDisplayRegion

                scrollControlsBottom =
                    scrollControlsTotalDisplayRegion.y + scrollControlsTotalDisplayRegion.height

                freeHeightAtBottom =
                    scrollControlsBottom
                        - (scrollHandle.totalDisplayRegion.y + scrollHandle.totalDisplayRegion.height)
            in
            if 10 < freeHeightAtBottom then
                Just
                    (describeBranch "Click at scroll control bottom"
                        (decideActionForCurrentStep
                            (EffectOnWindow.effectsMouseClickAtLocation
                                EffectOnWindow.MouseButtonLeft
                                { x = scrollControlsTotalDisplayRegion.x + 3
                                , y = scrollControlsBottom - 8
                                }
                                ++ [ EffectOnWindow.KeyDown EffectOnWindow.vkey_END
                                   , EffectOnWindow.KeyUp EffectOnWindow.vkey_END
                                   ]
                            )
                        )
                    )

            else
                Nothing


{-| Prepare a station name or structure name coming from bot-settings for comparing with menu entries.

  - The user could take the name from the info panel:
    The names sometimes differ between info panel and menu entries: 'Moon 7' can become 'M7'.

  - Do not distinguish between the comma and period characters:
    Besides the similar visual appearance, also because of the limitations of popular bot-settings parsing frameworks.
    The user can remove a comma or replace it with a full stop/period, whatever looks better.

-}
simplifyStationOrStructureNameFromSettingsBeforeComparingToMenuEntry : String -> String
simplifyStationOrStructureNameFromSettingsBeforeComparingToMenuEntry =
    String.toLower
        >> String.replace "moon " "m"
        >> String.replace "," ""
        >> String.replace "." ""
        >> String.trim


{-| 2020-07-11 Discovery by Viktor:
The entries for structures in the menu from the SurroundingsButton can be nested one level deeper than the ones for stations.
In other words, not all structures appear directly under the "structures" entry.
-}
dockAtRandomStationOrStructure :
    BotDecisionContext
    -> EveOnline.ParseUserInterface.ShipUI
    -> DecisionPathNode
dockAtRandomStationOrStructure context seeUndockingComplete =
    case fightRatsIfShipIsPointed context seeUndockingComplete of
        Just fightPointingRats ->
            fightPointingRats

        Nothing ->
            let
                withTextContainingIgnoringCase textToSearch =
                    List.filter (.text >> String.toLower >> (==) (textToSearch |> String.toLower)) >> List.head

                menuEntryIsSuitable menuEntry =
                    [ "cyno beacon", "jump gate" ]
                        |> List.any (\toAvoid -> menuEntry.text |> stringContainsIgnoringCase toAvoid)
                        |> not

                chooseNextMenuEntryDockOrRandom : Int -> UseContextMenuCascadeNode
                chooseNextMenuEntryDockOrRandom remainingDepth =
                    MenuEntryWithCustomChoice
                        { describeChoice = "Use 'Dock' if available or a random entry."
                        , chooseEntry =
                            \menu ->
                                let
                                    suitableMenuEntries =
                                        List.filter menuEntryIsSuitable menu.entries
                                in
                                case
                                    [ withTextContainingIgnoringCase "dock"
                                    , List.filter (.text >> stringContainsIgnoringCase "station")
                                        >> Common.Basics.listElementAtWrappedIndex
                                            (context.randomIntegers |> List.head |> Maybe.withDefault 0)
                                    , Common.Basics.listElementAtWrappedIndex
                                        (context.randomIntegers |> List.head |> Maybe.withDefault 0)
                                    ]
                                        |> Common.listMapFind (\priority -> suitableMenuEntries |> priority)
                                of
                                    Nothing ->
                                        Nothing

                                    Just menuEntry ->
                                        if remainingDepth <= 0 then
                                            Just ( menuEntry, MenuCascadeCompleted )

                                        else
                                            Just
                                                ( menuEntry
                                                , chooseNextMenuEntryDockOrRandom (remainingDepth - 1)
                                                )
                        }
            in
            useContextMenuCascadeOnListSurroundingsButton
                (useMenuEntryWithTextContainingFirstOfCommonContinuation [ "stations", "structures" ]
                    (chooseNextMenuEntryDockOrRandom 3)
                )
                context


-- 决定在太空中的下一步行动
-- 这是机器人在太空中的主要决策函数，处理是否需要隐藏或执行正常任务
decideNextActionWhenInSpace : BotDecisionContext -> EveOnline.ParseUserInterface.ShipUI -> DecisionPathNode
decideNextActionWhenInSpace context shipUI =
    case
        continueIfShouldHide
            { ifShouldHide =
                -- 如果需要隐藏，先回收无人机，然后逃离
                returnDronesToBay context
                    |> Maybe.withDefault
                        (describeBranch
                            "在配置的位置隐藏。"
                            (runAway context shipUI)
                        )
            }
            context
    of
        Just hideAction ->
            -- 如果需要隐藏，执行隐藏动作
            hideAction

        Nothing ->
            -- 不需要隐藏时，执行正常太空行动
            decideNextActionWhenInSpaceNotHiding context shipUI


-- 不需要隐藏时决定在太空中的下一步行动
decideNextActionWhenInSpaceNotHiding :
    BotDecisionContext
    -> EveOnline.ParseUserInterface.ShipUI
    -> DecisionPathNode
decideNextActionWhenInSpaceNotHiding context shipUI =
    if shipUIIndicatesShipIsWarpingOrJumping shipUI then
        -- 如果正在跃迁，执行跃迁时的动作
        describeBranch "我看到我们正在跃迁。"
            ([ returnDronesToBay context -- 回收无人机
             , deactivateModulesForWarp context -- 停用跃迁时不需要的模块
             , readShipUIModuleButtonTooltips context -- 读取船舶模块按钮提示
             ]
                |> List.filterMap identity
                |> List.head
                |> Maybe.withDefault waitForProgressInGame
            )

    else
        -- 不在跃迁时，检查模块状态
        readShipUIModuleButtonTooltips context
            |> Maybe.withDefault
                (case
                    -- 查找需要始终激活但目前未激活的模块
                    context
                        |> knownModulesToActivateAlways
                        |> List.filter (Tuple.second >> moduleIsActiveOrReloading >> not)
                        |> List.head
                 of
                    Just ( inactiveModuleMatchingText, inactiveModule ) ->
                        -- 激活需要始终开启的模块
                        describeBranch ("发现未激活的需要始终开启的模块 '" ++ inactiveModuleMatchingText ++ "'。激活它。")
                            (clickModuleButtonButWaitIfClickedInPreviousStep context inactiveModule)

                    Nothing ->
                        -- 所有需要始终激活的模块都已激活，继续执行下一步
                        modulesToActivateAlwaysActivated context shipUI
                )


-- 当所有需要始终激活的模块都已激活时的下一步决策
modulesToActivateAlwaysActivated :
    BotDecisionContext
    -> EveOnline.ParseUserInterface.ShipUI
    -> DecisionPathNode
modulesToActivateAlwaysActivated context shipUI =
    case fightRatsIfShipIsPointed context shipUI of
        Just fightPointingRats ->
            {- 应对特定情况：
                异常空间可能已消失（'site has despawned'），但仍有敌人在指向玩家飞船。
                因此，我们提高了与指向玩家的敌人战斗的优先级，使其独立于异常空间状态。
             -}
            fightPointingRats

        Nothing ->
            let
                returnDronesAndEnterAnomaly { ifNoAcceptableAnomalyAvailable } =
                    returnDronesToBay context
                        |> Maybe.withDefault
                            (describeBranch "No drones to return."
                                (enterAnomaly { ifNoAcceptableAnomalyAvailable = ifNoAcceptableAnomalyAvailable }
                                    context
                                    shipUI
                                )
                            )

                returnDronesAndEnterAnomalyOrWait =
                    returnDronesAndEnterAnomaly
                        { ifNoAcceptableAnomalyAvailable =
                            describeBranch "Wait for a matching anomaly to appear." waitForProgressInGame
                        }
            in
            case context.readingFromGameClient |> getCurrentAnomalyIDAsSeenInProbeScanner of
                Nothing ->
                    describeBranch "Looks like we are not in an anomaly." returnDronesAndEnterAnomalyOrWait

                Just anomalyID ->
                    case memoryOfAnomalyWithID anomalyID context.memory of
                        Nothing ->
                            describeBranch
                                ("Program error: Did not find memory of anomaly " ++ anomalyID)
                                waitForProgressInGame

                        Just memoryOfAnomaly ->
                            let
                                arrivalInAnomalyAgeSeconds =
                                    (context.eventContext.timeInMilliseconds - memoryOfAnomaly.arrivalTime.milliseconds) // 1000

                                continueInAnomaly : () -> DecisionPathNode
                                continueInAnomaly () =
                                    decideActionInAnomaly
                                        { arrivalInAnomalyAgeSeconds = arrivalInAnomalyAgeSeconds }
                                        context
                                        shipUI
                                        returnDronesAndEnterAnomalyOrWait
                            in
                            describeBranch ("We are in anomaly '" ++ anomalyID ++ "' since " ++ String.fromInt arrivalInAnomalyAgeSeconds ++ " seconds.")
                                (case findReasonToAvoidAnomalyFromMemory context { anomalyID = anomalyID } of
                                    Just reasonToAvoidAnomaly ->
                                        describeBranch
                                            ("Found a reason to avoid this anomaly: "
                                                ++ describeReasonToAvoidAnomaly reasonToAvoidAnomaly
                                            )
                                            (returnDronesAndEnterAnomaly
                                                { ifNoAcceptableAnomalyAvailable =
                                                    describeBranch "Get out of this anomaly."
                                                        (dockAtRandomStationOrStructure
                                                            context
                                                            shipUI
                                                        )
                                                }
                                            )

                                    Nothing ->
                                        continueInAnomaly ()
                                )


undockUsingStationWindow :
    BotDecisionContext
    -> { ifCannotReachButton : DecisionPathNode }
    -> DecisionPathNode
undockUsingStationWindow context { ifCannotReachButton } =
    case context.readingFromGameClient.stationWindow of
        Nothing ->
            describeBranch "I do not see the station window." ifCannotReachButton

        Just stationWindow ->
            case stationWindow.undockButton of
                Nothing ->
                    case stationWindow.abortUndockButton of
                        Nothing ->
                            describeBranch "I do not see the undock button." ifCannotReachButton

                        Just _ ->
                            describeBranch "I see we are already undocking." waitForProgressInGame

                Just undockButton ->
                    describeBranch "Click on the button to undock."
                        (mouseClickOnUIElement MouseButtonLeft undockButton
                            |> Result.Extra.unpack
                                (always ifCannotReachButton)
                                decideActionForCurrentStep
                        )


-- 在异常空间内决定下一步行动的函数
-- 这是机器人在异常空间中执行战斗任务的核心决策逻辑
decideActionInAnomaly :
    { arrivalInAnomalyAgeSeconds : Int } -- 到达异常空间的时间（秒）
    -- 决定在异常空间中的下一步行动
    -- 这个函数是机器人战斗行为的核心，处理目标锁定、攻击和战斗管理
    -> BotDecisionContext
    -> EveOnline.ParseUserInterface.ShipUI
    -> DecisionPathNode -- 战斗完成后的继续节点
    -> DecisionPathNode
decideActionInAnomaly { arrivalInAnomalyAgeSeconds } context shipUI continueIfCombatComplete =
    let
        -- 获取按照优先级排序的敌人列表
        ratsToAttackByPriority =
            ratsToAttackByPriorityFromContext context

        -- 展开优先级排序的敌人列表为单一列表
        overviewEntriesToAttack : List OverviewWindowEntry
        overviewEntriesToAttack =
            ratsToAttackByPriority.overviewEntriesByPrio
                |> List.concatMap (\( first, rest ) -> first :: rest)

        -- 获取需要锁定但尚未锁定的目标列表
        overviewEntriesToLock =
            overviewEntriesToAttack
                |> List.filter (overviewEntryIsTargetedOrTargeting >> not) -- 过滤掉已锁定或正在锁定的目标
                |> List.map (lockTargetFromOverviewEntry context) -- 创建锁定操作

        -- 确定是否需要解锁当前目标
        targetsToUnlock =
            if overviewEntriesToAttack |> List.any overviewEntryIsActiveTarget then
                [] -- 如果有需要攻击的目标是当前激活目标，则不解锁
            else
                context.readingFromGameClient.targets |> List.filter .isActiveTarget -- 否则解锁所有当前激活目标

        -- 获取所有概览条目
        overviewsAllEntries =
            context.readingFromGameClient.overviewWindows
                |> List.concatMap .entries

        -- 确定要环绕的对象
        maybeObjectToOrbit =
            case findObjectToOrbitByName context.eventContext.botSettings.orbitObjectNames overviewsAllEntries of
                Just fromName ->
                    Just fromName -- 使用配置的环绕对象
                Nothing ->
                    List.Extra.last overviewEntriesToAttack -- 如果没有配置环绕对象，则使用最后一个攻击目标

        -- 创建确保船舶正在环绕的决策
        ensureShipIsOrbitingDecision =
            case maybeObjectToOrbit of
                Nothing ->
                    Nothing -- 没有目标可以环绕
                Just objectToOrbit ->
                    ensureShipIsOrbiting shipUI objectToOrbit -- 执行环绕操作

        -- 计算在异常空间中的剩余等待时间
        waitTimeRemainingSeconds =
            context.eventContext.botSettings.anomalyWaitTimeSeconds - arrivalInAnomalyAgeSeconds

        -- 没有敌人可攻击时的决策
        decisionIfNoEnemyToAttack =
            if overviewEntriesToAttack |> List.isEmpty then
                -- 如果没有敌人，检查是否需要等待
                if waitTimeRemainingSeconds <= 0 then
                    -- 等待时间已过，回收无人机然后继续
                    returnDronesToBay context
                        |> Maybe.withDefault
                            (describeBranch "无无人机需要回收。" continueIfCombatComplete)
                else
                    -- 等待时间未过，继续等待
                    describeBranch
                        ("等待异常空间完成前的时间：" ++ String.fromInt waitTimeRemainingSeconds ++ " 秒")
                        waitForProgressInGame
            else
                -- 有敌人但尚未锁定完成，等待锁定
                describeBranch "等待目标锁定完成。" waitForProgressInGame

        -- 继续锁定概览条目的辅助函数
        continueLockOverviewEntries { ifNoEntryToLock } =
            case resultFirstSuccessOrFirstError overviewEntriesToLock of
                Nothing ->
                    -- 没有更多目标需要锁定
                    describeBranch "没有更多需要锁定的概览条目。"
                        ifNoEntryToLock
                Just nextOverviewEntryToLockResult ->
                    -- 锁定下一个目标
                    describeBranch "发现需要锁定的概览条目。"
                        (nextOverviewEntryToLockResult
                            |> Result.Extra.unpack
                                (describeBranch >> (|>) askForHelpToGetUnstuck)
                                identity
                        )

        -- 攻击敌人的决策逻辑
        decisionToKillRats =
            case targetsToUnlock of
                targetToUnlock :: _ ->
                    -- 需要解锁当前目标
                    describeBranch "发现需要解锁的目标。"
                        (useContextMenuCascade
                            ( "已锁定目标"
                            , targetToUnlock.barAndImageCont |> Maybe.withDefault targetToUnlock.uiNode
                            )
                            (useMenuEntryWithTextContaining "unlock" menuCascadeCompleted)
                            context
                        )
                [] ->
                    -- 使用无人机和武器模块攻击敌人
                    fightUsingDronesAndModules
                        { ifNoTarget = continueLockOverviewEntries { ifNoEntryToLock = decisionIfNoEnemyToAttack }
                        , lockNextTarget = continueLockOverviewEntries { ifNoEntryToLock = waitForProgressInGame }
                        , waitForProgress = waitForProgressInGame
                        }
                        context
                        shipUI
    in
    -- 根据配置决定是否在战斗中环绕目标
    if context.eventContext.botSettings.orbitInCombat == PromptParser.Yes then
        -- 如果启用环绕，执行环绕操作或战斗
        ensureShipIsOrbitingDecision
            |> Maybe.withDefault (Ok decisionToKillRats)
            |> Result.Extra.unpack
                (describeBranch >> (|>) decisionToKillRats)
                identity
    else
        -- 如果禁用环绕，直接执行战斗逻辑
        decisionToKillRats


findObjectToOrbitByName : List String -> List OverviewWindowEntry -> Maybe OverviewWindowEntry
findObjectToOrbitByName orbitObjectNames overviewEntries =
    overviewEntries
        |> List.Extra.find
            (\entry ->
                case entry.objectName of
                    Nothing ->
                        False

                    Just objectName ->
                        let
                            objectNameLower =
                                String.toLower objectName
                        in
                        List.any
                            (\objectNamePattern ->
                                String.contains (String.toLower objectNamePattern) objectNameLower
                            )
                            orbitObjectNames
            )


-- 进入异常空间函数
-- 此函数处理机器人如何选择和进入合适的异常空间进行战斗
enterAnomaly :
    { ifNoAcceptableAnomalyAvailable : DecisionPathNode }
    -> BotDecisionContext
    -> EveOnline.ParseUserInterface.ShipUI
    -> DecisionPathNode
enterAnomaly { ifNoAcceptableAnomalyAvailable } context shipUI =
    case context.readingFromGameClient.probeScannerWindow of
        Nothing ->
            describeBranch "找不到探针扫描窗口。" askForHelpToGetUnstuck

        Just probeScannerWindow ->
            -- 获取扫描结果并标记哪些需要忽略
            let
                scanResultsWithReasonToIgnore =
                    probeScannerWindow.scanResults
                        |> List.map
                            (\scanResult ->
                                ( scanResult
                                , findReasonToIgnoreProbeScanResult context scanResult
                                )
                            )
            in
            -- 从可接受的扫描结果中随机选择一个异常空间
            case
                scanResultsWithReasonToIgnore
                    |> List.filter (Tuple.second >> (==) Nothing) -- 过滤掉需要忽略的结果
                    |> List.map Tuple.first
                    |> listElementAtWrappedIndex (context.randomIntegers |> List.head |> Maybe.withDefault 0) -- 随机选择
            of
                Nothing ->
                    -- 没有找到合适的异常空间
                    describeBranch
                        ("我看到 "
                            ++ (probeScannerWindow.scanResults |> List.length |> String.fromInt)
                            ++ " 个扫描结果，但没有匹配的异常空间。等待匹配的异常空间出现。"
                        )
                        ifNoAcceptableAnomalyAvailable

                Just anomalyScanResult ->
                    -- 找到合适的异常空间，准备跃迁
                    describeBranch "跃迁到异常空间。"
                        (useContextMenuCascade
                            ( "扫描结果", anomalyScanResult.uiNode )
                            (useMenuEntryWithTextContaining "Warp to Within"
                                (useMenuEntryWithTextContaining
                                    context.eventContext.botSettings.warpToAnomalyDistance
                                    menuCascadeCompleted
                                )
                            )
                            context
                        )


-- 在跃迁前停用不需要的模块函数
-- 此函数负责识别并停用在跃迁过程中不需要的激活模块
deactivateModulesForWarp : BotDecisionContext -> Maybe DecisionPathNode
deactivateModulesForWarp context =
    let
        -- 找出需要停用的模块列表
        modulesToDeactivate : List ( String, EveOnline.ParseUserInterface.ShipUIModuleButton )
        modulesToDeactivate =
            case context.readingFromGameClient.shipUI of
                Nothing ->
                    []

                Just shipUI ->
                    shipUI.moduleButtons
                        |> List.filterMap
                            (\moduleButton ->
                                case moduleButton.isActive of
                                    Nothing ->
                                        Nothing

                                    Just False ->
                                        Nothing

                                    Just True ->
                                        moduleButton
                                            |> EveOnline.BotFramework.getModuleButtonTooltipFromModuleButton
                                                context.memory.shipModules
                                            |> Maybe.andThen
                                                (\tooltipMemory ->
                                                    -- 获取模块按钮的提示文本
                                                    let
                                                        tooltipText =
                                                            tooltipMemory.allContainedDisplayTextsWithRegion
                                                                |> List.map Tuple.first
                                                                |> String.join " "
                                                    in
                                                    -- 检查该模块是否在需要在跃迁时停用的列表中
                                                    if
                                                        context.eventContext.botSettings.deactivateModuleOnWarp
                                                            |> List.any (\moduleName -> tooltipText |> stringContainsIgnoringCase moduleName)
                                                    then
                                                        Just ( tooltipText, moduleButton )

                                                    else
                                                        Nothing
                                                )
                            )
    in
    -- 处理需要停用的模块
    case modulesToDeactivate of
        [] ->
            -- 没有需要停用的模块
            Nothing

        ( moduleName, moduleToDeactivate ) :: _ ->
            -- 点击停用模块以加速跃迁
            Just
                (describeBranch ("点击停用模块 '" ++ moduleName ++ "' 以加速跃迁。")
                    (clickModuleButtonButWaitIfClickedInPreviousStep context moduleToDeactivate)
                )


-- 当飞船被敌人指向时与敌人战斗的函数
-- 当检测到飞船被敌人指向时，此函数指导机器人如何攻击指向自己的敌人
fightRatsIfShipIsPointed :
    BotDecisionContext
    -> EveOnline.ParseUserInterface.ShipUI
    -> Maybe DecisionPathNode
fightRatsIfShipIsPointed context shipUI =
    {- 基于2024-04-24的观察：

       [...] "f" 键是命令无人机攻击当前锁定目标的快捷键。

       1. 如果是人类玩家，他会按住 "ctrl" 键并左键点击 "被指向" 图标。这会导致游戏自动锁定指向你的敌人。
       2. 一旦目标被锁定，他会按 'f' 键让无人机攻击那个敌人。或者他也可以右键点击无人机栏并选择攻击。
       3. 如果被多个敌人指向，则重复上述步骤。

    -}
    case offensiveBuffButtonsIndicatingSelfShipIsPointed shipUI of
        [] ->
            Nothing

        firstPointingBuffButton :: _ ->
            let
                lockTarget =
                    case mouseClickOnUIElement MouseButtonLeft firstPointingBuffButton of
                        Err _ ->
                            describeBranch "Failed to click"
                                askForHelpToGetUnstuck

                        Ok effectToClick ->
                            describeBranch "hold the 'ctrl' key while left clicking the 'pointed' symbol"
                                (decideActionForCurrentStep
                                    (List.concat
                                        [ [ EffectOnWindow.KeyDown EffectOnWindow.vkey_CONTROL ]
                                        , effectToClick
                                        , [ EffectOnWindow.KeyUp EffectOnWindow.vkey_CONTROL ]
                                        ]
                                    )
                                )
            in
            Just
                (describeBranch "I see a buff indicating the ship is pointed."
                    (fightUsingDronesAndModules
                        { ifNoTarget = lockTarget
                        , lockNextTarget = lockTarget
                        , waitForProgress = waitForProgressInGame
                        }
                        context
                        shipUI
                    )
                )


-- 使用无人机和武器模块进行战斗的核心函数
-- 这个函数处理目标选择、武器激活和无人机控制的战斗逻辑
fightUsingDronesAndModules :
    { ifNoTarget : DecisionPathNode, lockNextTarget : DecisionPathNode, waitForProgress : DecisionPathNode } -- 配置参数
    -> BotDecisionContext
    -> EveOnline.ParseUserInterface.ShipUI
    -> DecisionPathNode
fightUsingDronesAndModules config context shipUI =
    let
        -- 获取按优先级排序的攻击目标
        ratsToAttackByPriority =
            ratsToAttackByPriorityFromContext context

        -- 提取最高优先级的目标列表
        highPrioTargets : List EveOnline.ParseUserInterface.Target
        highPrioTargets =
            case ratsToAttackByPriority.targetsByPrio of
                [] ->
                    []
                ( first, rest ) :: _ ->
                    first :: rest -- 第一个目标优先级最高，加上同一优先级的其他目标
    in
    -- 检查是否有锁定的目标
    case context.readingFromGameClient.targets of
        [] ->
            -- 没有锁定目标，执行配置的无目标行为
            describeBranch "没有锁定的目标。"
                config.ifNoTarget

        _ :: _ ->
            -- 有锁定目标，继续战斗逻辑
            describeBranch "发现锁定的目标。"
                (case checkActiveTargetIsOfHighestPriority ratsToAttackByPriority context.readingFromGameClient of
                    -- 检查当前激活目标是否是最高优先级，如果不是，切换到高优先级目标
                    Just selectHighPrio ->
                        selectHighPrio

                    Nothing ->
                        -- 激活目标已经是最高优先级，检查武器模块
                        case
                            shipUI
                                |> shipUIModulesToActivateOnTarget -- 获取应该激活的武器模块
                                |> List.filter (.isActive >> Maybe.withDefault False >> not) -- 过滤掉未激活的模块
                                |> List.head -- 获取第一个需要激活的模块
                        of
                            Nothing ->
                                -- 所有武器模块都已激活，处理无人机
                                describeBranch "所有攻击模块都已激活。"
                                    (launchAndEngageDrones { redirectToTargets = Just highPrioTargets } context
                                        -- 确保无人机正在攻击目标
                                        |> Maybe.withDefault
                                            (describeBranch "没有空闲的无人机。"
                                                -- 检查是否需要锁定更多目标
                                                (if context.eventContext.botSettings.maxTargetCount <= (context.readingFromGameClient.targets |> List.length) then
                                                    -- 已达到最大锁定目标数，等待战斗进展
                                                    describeBranch "已锁定足够的目标。" config.waitForProgress
                                                 else
                                                    -- 锁定下一个目标
                                                    config.lockNextTarget
                                                )
                                            )
                                    )

                            Just inactiveModule ->
                                -- 发现未激活的武器模块，激活它
                                describeBranch "发现需要在目标上激活的未激活模块。正在激活。"
                                    (clickModuleButtonButWaitIfClickedInPreviousStep context inactiveModule)
                )


-- 根据上下文计算攻击目标的优先级
-- 这个函数决定机器人应该优先攻击哪些敌人目标
ratsToAttackByPriorityFromContext : BotDecisionContext -> RatsByAttackPriority
ratsToAttackByPriorityFromContext context =
    let
        prioritizedRatsPatterns : List String
        prioritizedRatsPatterns =
            List.map String.toLower context.eventContext.botSettings.prioritizeRats

        isPriorityRat : { a | labelText : String } -> Bool
        isPriorityRat objectInSpace =
            prioritizedRatsPatterns
                |> List.any
                    (\priorityRat ->
                        String.contains
                            priorityRat
                            (String.toLower objectInSpace.labelText)
                    )

        attackPriority : { a | labelText : String } -> Int
        attackPriority objectInSpace =
            if isPriorityRat objectInSpace then
                0

            else
                1

        overviewEntriesToAttack =
            context.readingFromGameClient.overviewWindows
                |> List.concatMap .entries
                |> List.filter shouldAttackOverviewEntry

        overviewEntriesByPrio : List ( OverviewWindowEntry, List OverviewWindowEntry )
        overviewEntriesByPrio =
            overviewEntriesToAttack
                {-
                   2023-03-30
                   Change to sort by display location after Wombat shared his experience in EVE Online at https://forum.botlab.org/t/eve-online-anomaly-ratting-bot-release/87/340
                   |> List.sortBy (.objectDistanceInMeters >> Result.withDefault 999999)
                -}
                |> List.sortBy (.uiNode >> .totalDisplayRegion >> .y)
                |> Common.Basics.listGatherEqualsBy
                    (\overviewEntry -> attackPriority { labelText = Maybe.withDefault "" overviewEntry.objectName })
                |> List.sortBy Tuple.first
                |> List.map Tuple.second

        targetsByPrio : List ( EveOnline.ParseUserInterface.Target, List EveOnline.ParseUserInterface.Target )
        targetsByPrio =
            context.readingFromGameClient.targets
                |> Common.Basics.listGatherEqualsBy
                    (\target -> attackPriority { labelText = String.join " " target.textsTopToBottom })
                |> List.sortBy Tuple.first
                |> List.map Tuple.second
    in
    { overviewEntriesByPrio = overviewEntriesByPrio
    , targetsByPrio = targetsByPrio
    }


ensureShipIsOrbiting : ShipUI -> OverviewWindowEntry -> Maybe (Result String DecisionPathNode)
ensureShipIsOrbiting shipUI overviewEntryToOrbit =
    if (shipUI.indication |> Maybe.andThen .maneuverType) == Just EveOnline.ParseUserInterface.ManeuverOrbit then
        Nothing

    else
        Just
            (case mouseClickOnUIElement MouseButtonLeft overviewEntryToOrbit.uiNode of
                Err _ ->
                    Err "Failed to click"

                Ok effectToClick ->
                    Ok
                        (describeBranch "Press the 'W' key and click on the overview entry."
                            (decideActionForCurrentStep
                                ([ [ EffectOnWindow.KeyDown EffectOnWindow.vkey_W ]
                                 , effectToClick
                                 , [ EffectOnWindow.KeyUp EffectOnWindow.vkey_W ]
                                 ]
                                    |> List.concat
                                )
                            )
                        )
            )


-- 控制无人机发射和战斗行为的核心函数
-- 此函数负责管理无人机的发射、攻击和重新分配目标
launchAndEngageDrones :
    { redirectToTargets : Maybe (List EveOnline.ParseUserInterface.Target) }
    -> BotDecisionContext
    -> Maybe DecisionPathNode
launchAndEngageDrones config context =
    case context.readingFromGameClient.dronesWindow of
        Nothing ->
            Nothing

        Just dronesWindow ->
            case ( dronesWindow.droneGroupInBay, dronesWindow.droneGroupInSpace ) of
                ( Just droneGroupInBay, Just droneGroupInSpace ) ->
                    let
                        idlingDrones : List EveOnline.ParseUserInterface.DronesWindowEntryDroneStructure
                        idlingDrones =
                            droneGroupInSpace
                                |> EveOnline.ParseUserInterface.enumerateAllDronesFromDronesGroup
                                |> List.filter
                                    (.uiNode
                                        >> .uiNode
                                        >> EveOnline.ParseUserInterface.getAllContainedDisplayTexts
                                        >> List.any (stringContainsIgnoringCase "idle")
                                    )

                        dronesInBayQuantity : Int
                        dronesInBayQuantity =
                            case droneGroupInBay.header.quantityFromTitle of
                                Nothing ->
                                    0

                                Just quantityFromTitle ->
                                    quantityFromTitle.current

                        dronesInSpaceQuantityCurrent : Int
                        dronesInSpaceQuantityCurrent =
                            case droneGroupInSpace.header.quantityFromTitle of
                                Nothing ->
                                    0

                                Just quantityFromTitle ->
                                    quantityFromTitle.current

                        dronesInSpaceQuantityLimit : Int
                        dronesInSpaceQuantityLimit =
                            case droneGroupInSpace.header.quantityFromTitle of
                                Nothing ->
                                    2

                                Just quantityFromTitle ->
                                    case quantityFromTitle.maximum of
                                        Nothing ->
                                            2

                                        Just maximum ->
                                            maximum

                        {-
                           Observation from session-recording-2024-05-07T11-55-13.zip-event-482-eve-online-memory-reading:
                           The 'Sprite' UI node referenced from 'assignedIcons' has the following property we can use as indication:
                           _hint = "Drones\nWasp II: 5"
                        -}
                        targetsWithDronesAssigned : List EveOnline.ParseUserInterface.Target
                        targetsWithDronesAssigned =
                            context.readingFromGameClient.targets
                                |> List.filter
                                    (\target ->
                                        target.assignedIcons
                                            |> List.any
                                                (\assignedIcon ->
                                                    assignedIcon.uiNode
                                                        |> EveOnline.ParseUserInterface.getHintTextFromDictEntries
                                                        |> Maybe.map (stringContainsIgnoringCase "drone")
                                                        |> Maybe.withDefault False
                                                )
                                    )

                        engageDrones : DecisionPathNode
                        engageDrones =
                            useContextMenuCascade
                                ( "drones group", droneGroupInSpace.header.uiNode )
                                (useMenuEntryWithTextContaining "engage target" menuCascadeCompleted)
                                context

                        considerLaunch : () -> Maybe DecisionPathNode
                        considerLaunch () =
                            if 0 < dronesInBayQuantity && dronesInSpaceQuantityCurrent < dronesInSpaceQuantityLimit then
                                if assumeNotEnoughBandwidthToLaunchDrone context then
                                    Nothing

                                else
                                    Just
                                        (describeBranch "Launch drones"
                                            (useContextMenuCascade
                                                ( "drones group", droneGroupInBay.header.uiNode )
                                                (useMenuEntryWithTextContaining "Launch drone" menuCascadeCompleted)
                                                context
                                            )
                                        )

                            else
                                Nothing
                    in
                    if 0 < List.length idlingDrones then
                        Just
                            (describeBranch "Engage idling drone(s)" engageDrones)

                    else
                        case config.redirectToTargets of
                            Nothing ->
                                considerLaunch ()

                            Just redirectToTargets ->
                                let
                                    targetsWithDronesAssignedLowPrio : List EveOnline.ParseUserInterface.Target
                                    targetsWithDronesAssignedLowPrio =
                                        List.filter
                                            (\target -> not (List.member target redirectToTargets))
                                            targetsWithDronesAssigned
                                in
                                if 0 < List.length targetsWithDronesAssignedLowPrio then
                                    Just
                                        (describeBranch "Redirect drones to high prio target"
                                            (case checkActiveTargetIsInGroup redirectToTargets context.readingFromGameClient of
                                                Just selectHighPrio ->
                                                    selectHighPrio

                                                Nothing ->
                                                    engageDrones
                                            )
                                        )

                                else
                                    considerLaunch ()

                _ ->
                    Nothing


-- 检查当前激活的目标是否是最高优先级的目标
-- 这个函数确保机器人总是优先攻击威胁最大的敌人
checkActiveTargetIsOfHighestPriority :
    RatsByAttackPriority
    -> ReadingFromGameClient
    -> Maybe DecisionPathNode
checkActiveTargetIsOfHighestPriority ratsToAttackByPriority readingFromGameClient =
    case ratsToAttackByPriority.targetsByPrio of
        [] ->
            Nothing

        ( first, rest ) :: _ ->
            checkActiveTargetIsInGroup
                (first :: rest)
                readingFromGameClient


checkActiveTargetIsInGroup :
    List EveOnline.ParseUserInterface.Target
    -> ReadingFromGameClient
    -> Maybe DecisionPathNode
checkActiveTargetIsInGroup priorityTargets readingFromGameClient =
    case priorityTargets of
        [] ->
            Nothing

        firstHighPrio :: _ ->
            let
                activeTargets : List EveOnline.ParseUserInterface.Target
                activeTargets =
                    List.filter .isActiveTarget readingFromGameClient.targets

                activeTargetsLowPrio : List EveOnline.ParseUserInterface.Target
                activeTargetsLowPrio =
                    List.filter (\target -> not (List.member target priorityTargets)) activeTargets
            in
            case activeTargetsLowPrio of
                [] ->
                    Nothing

                _ :: _ ->
                    Just
                        (describeBranch "The active target is not the highest priority. Activating highest priority target."
                            {-
                               As shared 2024-05-08:
                               > [...] Once a rat is targeted, a player will left click the targeted rat from the target list [...]
                            -}
                            (case mouseClickOnUIElement MouseButtonLeft firstHighPrio.uiNode of
                                Err _ ->
                                    describeBranch "Failed to click"
                                        askForHelpToGetUnstuck

                                Ok effectToClick ->
                                    decideActionForCurrentStep effectToClick
                            )
                        )


assumeNotEnoughBandwidthToLaunchDrone : BotDecisionContext -> Bool
assumeNotEnoughBandwidthToLaunchDrone context =
    case
        context.readingFromGameClient.dronesWindow
            |> Maybe.andThen .droneGroupInSpace
            |> Maybe.andThen (.header >> .quantityFromTitle)
    of
        Nothing ->
            True

        Just inSpaceQuantity ->
            let
                limitsFromPreviousEvents =
                    context.memory.droneBandwidthLimitatatinEvents
                        |> List.filter
                            (\limitEvent ->
                                context.eventContext.timeInMilliseconds < limitEvent.timeMilliseconds + 300 * 1000
                            )
                        |> List.map .dronesInSpaceCount

                limitFromPreviousEvents =
                    limitsFromPreviousEvents
                        |> List.sort
                        -- Require confirmation via multiple observations
                        |> List.drop 1
                        |> List.head
                        |> Maybe.withDefault 999
            in
            context.memory.notEnoughBandwidthToLaunchDrone
                || (limitFromPreviousEvents <= inSpaceQuantity.current)


returnDronesToBay : BotDecisionContext -> Maybe DecisionPathNode
returnDronesToBay context =
    case context.readingFromGameClient.dronesWindow of
        Nothing ->
            Nothing

        Just dronesWindow ->
            case dronesWindow.droneGroupInSpace of
                Nothing ->
                    Nothing

                Just droneGroupInLocalSpace ->
                    if
                        (droneGroupInLocalSpace.header.quantityFromTitle
                            |> Maybe.map .current
                            |> Maybe.withDefault 0
                        )
                            < 1
                    then
                        Nothing

                    else
                        Just
                            (describeBranch "I see there are drones in space. Return those to bay."
                                (useContextMenuCascade
                                    ( "drones group", droneGroupInLocalSpace.header.uiNode )
                                    (useMenuEntryWithTextContaining "Return to drone bay" menuCascadeCompleted)
                                    context
                                )
                            )


-- 从总览表中锁定目标
-- 这个函数创建锁定特定总览条目的决策路径
lockTargetFromOverviewEntry :
    BotDecisionContext
    -> OverviewWindowEntry
    -> Result String DecisionPathNode
lockTargetFromOverviewEntry context overviewEntry =
    if uiNodeVisibleRegionLargeEnoughForClicking overviewEntry.uiNode then
        Ok
            (describeBranch ("Lock target from overview entry '" ++ (overviewEntry.objectName |> Maybe.withDefault "") ++ "'")
                (useContextMenuCascadeOnOverviewEntry
                    (useMenuEntryWithTextEqual "Lock target" menuCascadeCompleted)
                    overviewEntry
                    context
                )
            )

    else
        Err "Unable to click this overview entry because more of it needs to be visible."


readShipUIModuleButtonTooltips : BotDecisionContext -> Maybe DecisionPathNode
readShipUIModuleButtonTooltips =
    EveOnline.BotFrameworkSeparatingMemory.readShipUIModuleButtonTooltipWhereNotYetInMemory


knownModulesToActivateAlways : BotDecisionContext -> List ( String, EveOnline.ParseUserInterface.ShipUIModuleButton )
knownModulesToActivateAlways context =
    context.readingFromGameClient.shipUI
        |> Maybe.map .moduleButtons
        |> Maybe.withDefault []
        |> List.filterMap
            (\moduleButton ->
                moduleButton
                    |> EveOnline.BotFramework.getModuleButtonTooltipFromModuleButton context.memory.shipModules
                    |> Maybe.andThen (tooltipLooksLikeModuleToActivateAlways context)
                    |> Maybe.map (\moduleName -> ( moduleName, moduleButton ))
            )


tooltipLooksLikeModuleToActivateAlways : BotDecisionContext -> ModuleButtonTooltipMemory -> Maybe String
tooltipLooksLikeModuleToActivateAlways context =
    .allContainedDisplayTextsWithRegion
        >> List.filterMap
            (\( tooltipText, _ ) ->
                context.eventContext.botSettings.activateModulesAlways
                    |> List.filterMap
                        (\moduleToActivateAlways ->
                            if tooltipText |> stringContainsIgnoringCase moduleToActivateAlways then
                                Just tooltipText

                            else
                                Nothing
                        )
                    |> List.head
            )
        >> List.head


botMain : InterfaceToHost.BotConfig State
botMain =
    { init = EveOnline.BotFrameworkSeparatingMemory.initState initBotMemory
    , processEvent =
        EveOnline.BotFrameworkSeparatingMemory.processEvent
            { parseBotSettings = parseBotSettings
            , selectGameClientInstance = always EveOnline.BotFramework.selectGameClientInstanceWithTopmostWindow
            , updateMemoryForNewReadingFromGame = updateMemoryForNewReadingFromGame
            , statusTextFromDecisionContext = statusTextFromState
            , decideNextStep = anomalyBotDecisionRoot
            }
    }
        |> EveOnline.UnstuckBot.botResolvingStuck


initBotMemory : BotMemory
initBotMemory =
    { lastDockedStationNameFromInfoPanel = Nothing
    , shipModules = EveOnline.BotFramework.initShipModulesMemory
    , overviewWindows = EveOnline.BotFramework.initOverviewWindowsMemory
    , shipWarpingInLastReading = Nothing
    , visitedAnomalies = Dict.empty
    , notEnoughBandwidthToLaunchDrone = False
    , droneBandwidthLimitatatinEvents = []
    }


-- 生成机器人当前状态的文本描述
-- 这个函数收集并格式化机器人的各种状态信息，包括战斗统计、飞船状态、无人机状态和当前异常空间信息
statusTextFromState : BotDecisionContext -> String
statusTextFromState context =
    let
        -- 获取当前游戏客户端的读取数据
        readingFromGameClient =
            context.readingFromGameClient

        -- 生成性能统计信息（已访问的异常空间数量）
        describePerformance =
            "已访问异常空间: " ++ (context.memory.visitedAnomalies |> Dict.size |> String.fromInt) ++ "个。"

        -- 生成当前状态读取信息
        describeCurrentReading =
            case readingFromGameClient.shipUI of
                -- 如果看不到飞船UI，可能处于停靠状态
                Nothing ->
                    [ "未检测到飞船UI。可能处于停靠状态。" ]

                -- 如果看到飞船UI，收集详细信息
                Just shipUI ->
                    let
                        -- 生成飞船护盾状态描述
                        describeShip =
                            "护盾值: " ++ (shipUI.hitpointsPercent.shield |> String.fromInt) ++ "%。"

                        -- 生成无人机状态描述
                        describeDrones =
                            case readingFromGameClient.dronesWindow of
                                Nothing ->
                                    "未检测到无人机窗口。"
                                Just dronesWindow ->
                                    "已检测到无人机窗口: 无人机舱中: "
                                        ++ (dronesWindow.droneGroupInBay
                                                |> Maybe.andThen (.header >> .quantityFromTitle)
                                                |> Maybe.map (.current >> String.fromInt)
                                                |> Maybe.withDefault "未知"
                                           )
                                        ++ "架, 太空中: "
                                        ++ (dronesWindow.droneGroupInSpace
                                                |> Maybe.andThen (.header >> .quantityFromTitle)
                                                |> Maybe.map (.current >> String.fromInt)
                                                |> Maybe.withDefault "未知"
                                           )
                                        ++ "架。"

                        -- 获取总览表中其他飞行员的名称
                        namesOfOtherPilotsInOverview =
                            getNamesOfOtherPilotsInOverview readingFromGameClient

                        -- 生成当前异常空间描述
                        describeAnomaly =
                            "当前异常空间: "
                                ++ (getCurrentAnomalyIDAsSeenInProbeScanner readingFromGameClient |> Maybe.withDefault "无")
                                ++ "。"

                        -- 生成总览表中其他玩家描述
                        describeOverview =
                            ("总览表中发现 "
                                ++ (namesOfOtherPilotsInOverview |> List.length |> String.fromInt)
                                ++ " 名其他飞行员"
                            )
                                ++ (if namesOfOtherPilotsInOverview == [] then
                                        ""
                                    else
                                        ": " ++ (namesOfOtherPilotsInOverview |> String.join ", ")
                                   )
                                ++ "。"
                    in
                    -- 将不同类别的信息分组并合并
                    [ [ describeShip ]
                    , [ describeDrones ]
                    , [ describeAnomaly, describeOverview ]
                    ]
                        |> List.map (String.join " ") -- 合并每组中的信息
    in
    -- 合并所有信息并以换行符分隔
    [ [ describePerformance ]
    , describeCurrentReading
    ]
        |> List.concat
        |> String.join "\n"


overviewEntryIsTargetedOrTargeting : EveOnline.ParseUserInterface.OverviewWindowEntry -> Bool
overviewEntryIsTargetedOrTargeting overviewEntry =
    overviewEntry.commonIndications.targetedByMe || overviewEntry.commonIndications.targeting


overviewEntryIsActiveTarget : EveOnline.ParseUserInterface.OverviewWindowEntry -> Bool
overviewEntryIsActiveTarget =
    .namesUnderSpaceObjectIcon
        >> Set.member "myActiveTargetIndicator"


shouldAttackOverviewEntry : EveOnline.ParseUserInterface.OverviewWindowEntry -> Bool
shouldAttackOverviewEntry =
    iconSpriteHasColorOfRat


moduleIsActiveOrReloading : EveOnline.ParseUserInterface.ShipUIModuleButton -> Bool
moduleIsActiveOrReloading moduleButton =
    (moduleButton.isActive |> Maybe.withDefault False)
        || ((moduleButton.rampRotationMilli |> Maybe.withDefault 0) /= 0)


iconSpriteHasColorOfRat : EveOnline.ParseUserInterface.OverviewWindowEntry -> Bool
iconSpriteHasColorOfRat overviewEntry =
    case overviewEntry.iconSpriteColorPercent of
        Nothing ->
            False

        Just colorPercent ->
            (colorPercent.g * 3 < colorPercent.r)
                && (colorPercent.b * 3 < colorPercent.r)
                && (60 < colorPercent.r && 50 < colorPercent.a)


updateMemoryForNewReadingFromGame : UpdateMemoryContext -> BotMemory -> BotMemory
updateMemoryForNewReadingFromGame context botMemoryBefore =
    let
        currentStationNameFromInfoPanel : Maybe String
        currentStationNameFromInfoPanel =
            context.readingFromGameClient.infoPanelContainer
                |> Maybe.andThen .infoPanelLocationInfo
                |> Maybe.andThen .expandedContent
                |> Maybe.andThen .currentStationName

        shipIsWarping : Maybe Bool
        shipIsWarping =
            case context.readingFromGameClient.shipUI of
                Nothing ->
                    Nothing

                Just shipUI ->
                    case shipUI.indication of
                        Nothing ->
                            Nothing

                        Just indication ->
                            case indication.maneuverType of
                                Nothing ->
                                    Nothing

                                Just maneuverType ->
                                    case maneuverType of
                                        EveOnline.ParseUserInterface.ManeuverWarp ->
                                            Just True

                                        _ ->
                                            Just False

        namesOfRatsInOverview : List String
        namesOfRatsInOverview =
            getNamesOfRatsInOverview context.readingFromGameClient

        weJustFinishedWarping : Bool
        weJustFinishedWarping =
            case botMemoryBefore.shipWarpingInLastReading of
                Just True ->
                    shipIsWarping /= botMemoryBefore.shipWarpingInLastReading

                _ ->
                    False

        visitedAnomalies : Dict.Dict String MemoryOfAnomaly
        visitedAnomalies =
            if shipIsWarping == Just True then
                botMemoryBefore.visitedAnomalies

            else
                case context.readingFromGameClient |> getCurrentAnomalyIDAsSeenInProbeScanner of
                    Nothing ->
                        botMemoryBefore.visitedAnomalies

                    Just currentAnomalyID ->
                        let
                            anomalyMemoryBefore =
                                botMemoryBefore.visitedAnomalies
                                    |> Dict.get currentAnomalyID
                                    |> Maybe.withDefault
                                        { arrivalTime = { milliseconds = context.timeInMilliseconds }
                                        , otherPilotsFoundOnArrival = []
                                        , ratsSeen = Set.empty
                                        }

                            anomalyMemoryWithOtherPilotsOnArrival =
                                if weJustFinishedWarping then
                                    { anomalyMemoryBefore
                                        | otherPilotsFoundOnArrival = getNamesOfOtherPilotsInOverview context.readingFromGameClient
                                    }

                                else
                                    anomalyMemoryBefore

                            anomalyMemory =
                                { anomalyMemoryWithOtherPilotsOnArrival
                                    | ratsSeen =
                                        Set.union anomalyMemoryBefore.ratsSeen (Set.fromList namesOfRatsInOverview)
                                }
                        in
                        botMemoryBefore.visitedAnomalies
                            |> Dict.insert currentAnomalyID anomalyMemory

        notEnoughBandwidthToLaunchDrone : Bool
        notEnoughBandwidthToLaunchDrone =
            readingFromGameClientSaysNotEnoughBandwidthToLaunchDrone context.readingFromGameClient

        droneBandwidthLimitatatinEvents =
            case context.readingFromGameClient.dronesWindow of
                Nothing ->
                    -- Also reset when docked
                    []

                Just dronesWindow ->
                    let
                        dronesInSpaceCount =
                            dronesWindow.droneGroupInSpace
                                |> Maybe.andThen (.header >> .quantityFromTitle)
                                |> Maybe.map .current
                                |> Maybe.withDefault 0

                        newEvents =
                            if notEnoughBandwidthToLaunchDrone && not botMemoryBefore.notEnoughBandwidthToLaunchDrone then
                                [ { timeMilliseconds = context.timeInMilliseconds
                                  , dronesInSpaceCount = dronesInSpaceCount
                                  }
                                ]

                            else
                                []
                    in
                    newEvents ++ botMemoryBefore.droneBandwidthLimitatatinEvents
    in
    { lastDockedStationNameFromInfoPanel =
        [ currentStationNameFromInfoPanel, botMemoryBefore.lastDockedStationNameFromInfoPanel ]
            |> List.filterMap identity
            |> List.head
    , shipModules =
        botMemoryBefore.shipModules
            |> EveOnline.BotFramework.integrateCurrentReadingsIntoShipModulesMemory context.readingFromGameClient
    , overviewWindows =
        botMemoryBefore.overviewWindows
            |> EveOnline.BotFramework.integrateCurrentReadingsIntoOverviewWindowsMemory context.readingFromGameClient
    , shipWarpingInLastReading = shipIsWarping
    , visitedAnomalies = visitedAnomalies
    , notEnoughBandwidthToLaunchDrone = notEnoughBandwidthToLaunchDrone
    , droneBandwidthLimitatatinEvents = droneBandwidthLimitatatinEvents |> List.take 4
    }


getCurrentAnomalyIDAsSeenInProbeScanner : ReadingFromGameClient -> Maybe String
getCurrentAnomalyIDAsSeenInProbeScanner =
    .probeScannerWindow
        >> Maybe.map getScanResultsForSitesOnGrid
        >> Maybe.withDefault []
        >> List.head
        >> Maybe.andThen (.cellsTexts >> Dict.get "ID")


getScanResultsForSitesOnGrid : EveOnline.ParseUserInterface.ProbeScannerWindow -> List EveOnline.ParseUserInterface.ProbeScanResult
getScanResultsForSitesOnGrid probeScannerWindow =
    probeScannerWindow.scanResults
        |> List.filter (scanResultLooksLikeItIsOnGrid >> Maybe.withDefault False)


scanResultLooksLikeItIsOnGrid : EveOnline.ParseUserInterface.ProbeScanResult -> Maybe Bool
scanResultLooksLikeItIsOnGrid =
    .cellsTexts
        >> Dict.get "Distance"
        >> Maybe.map (\text -> (text |> String.contains " m") || (text |> String.contains " km"))


getNamesOfOtherPilotsInOverview : ReadingFromGameClient -> List String
getNamesOfOtherPilotsInOverview readingFromGameClient =
    let
        pilotNamesFromLocalChat =
            readingFromGameClient
                |> localChatWindowFromUserInterface
                |> Maybe.andThen .userlist
                |> Maybe.map .visibleUsers
                |> Maybe.withDefault []
                |> List.filterMap .name

        overviewEntryRepresentsOtherPilot overviewEntry =
            (overviewEntry.objectName |> Maybe.map (\objectName -> pilotNamesFromLocalChat |> List.member objectName))
                |> Maybe.withDefault False
    in
    readingFromGameClient.overviewWindows
        |> List.concatMap .entries
        |> List.filter overviewEntryRepresentsOtherPilot
        |> List.map (.objectName >> Maybe.withDefault "do not see name of overview entry")


getNamesOfRatsInOverview : ReadingFromGameClient -> List String
getNamesOfRatsInOverview readingFromGameClient =
    let
        overviewEntryRepresentsRatOnGrid overviewEntry =
            iconSpriteHasColorOfRat overviewEntry
                && (overviewEntry.objectDistanceInMeters
                        |> Result.map (\distanceInMeters -> distanceInMeters < 300000)
                        |> Result.withDefault False
                   )
    in
    readingFromGameClient.overviewWindows
        |> List.concatMap .entries
        |> List.filter overviewEntryRepresentsRatOnGrid
        |> List.map (.objectName >> Maybe.withDefault "do not see name of overview entry")


shipUIModulesToActivateOnTarget : EveOnline.ParseUserInterface.ShipUI -> List ShipUIModuleButton
shipUIModulesToActivateOnTarget shipUI =
    shipUI.moduleButtonsRows.top


nothingFromIntIfGreaterThan : Int -> Int -> Maybe Int
nothingFromIntIfGreaterThan limit originalInt =
    if limit < originalInt then
        Nothing

    else
        Just originalInt


readingFromGameClientSaysNotEnoughBandwidthToLaunchDrone : ReadingFromGameClient -> Bool
readingFromGameClientSaysNotEnoughBandwidthToLaunchDrone reading =
    reading.layerAbovemain
        |> Maybe.map (.uiNode >> EveOnline.ParseUserInterface.getAllContainedDisplayTextsWithRegion)
        |> Maybe.withDefault []
        |> List.map Tuple.first
        |> List.any abovemainMessageSaysNotEnoughBandwidthToLaunchDrone


{-| Returns the subsequence of offensive buff buttons from the ship UI that indicated that our own ship is pointed.

Classifation sources:

  - Discussion of session-recording-2024-04-05T17

-}
offensiveBuffButtonsIndicatingSelfShipIsPointed :
    EveOnline.ParseUserInterface.ShipUI
    -> List EveOnline.ParseUserInterface.UITreeNodeWithDisplayRegion
offensiveBuffButtonsIndicatingSelfShipIsPointed shipUI =
    List.filterMap
        (\offensiveBuffButton ->
            if offensiveBuffButtonNameIndicatesSelfShipIsPointed offensiveBuffButton.name then
                Just offensiveBuffButton.uiNode

            else
                Nothing
        )
        shipUI.offensiveBuffButtons


offensiveBuffButtonNameIndicatesSelfShipIsPointed : String -> Bool
offensiveBuffButtonNameIndicatesSelfShipIsPointed offensiveBuffButtonName =
    case String.toLower offensiveBuffButtonName of
        "warpscrambler" ->
            True

        "webify" ->
            True

        _ ->
            False


abovemainMessageSaysNotEnoughBandwidthToLaunchDrone : String -> Bool
abovemainMessageSaysNotEnoughBandwidthToLaunchDrone message =
    {-
       Observed in session-recording-2023-04-08T19-20-34.zip-event-285-eve-online-memory-reading:
       <center>You don't have enough bandwidth to launch Berserker II. You need 25.0 Mbit/s but only have 0.0 Mbit/s available.
    -}
    String.contains "don't have enough bandwidth to launch" message


randomIntFromInterval : BotDecisionContext -> IntervalInt -> Int
randomIntFromInterval context interval =
    let
        randomInteger =
            context.randomIntegers
                |> List.head
                |> Maybe.withDefault 0

        intervalLength =
            interval.maximum - interval.minimum
    in
    if intervalLength < 1 then
        interval.minimum

    else
        interval.minimum + (randomInteger |> modBy intervalLength)
