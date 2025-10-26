# 为EVE Online开发

你是否曾经想了解为EVE Online创建机器人或情报工具的过程？
本指南将带你了解这个过程，并帮助你自定义机器人。

在学习如何简单自定义现有机器人后，我们将探索用于开发最先进机器人的技术和工具，这些机器人可以自主执行各种游戏内活动，如挖矿、刷怪、交易和连续几小时执行任务。

在某种程度上，这是我从开发项目中获得的经验总结。但更重要的是，本指南是你反馈的产物。感谢你无数的问题和建议，使本指南成为今天的样子。

## 最简单的自定义机器人

在这个练习中，我们采用最快的方法来创建自定义机器人，从互联网上发布的开源机器人开始。
让我们运行这个自动导航机器人：

<https://github.com/Viir/bots/tree/9567e5b6d7982c4feeed05fef1a24705e8510bfc/implement/applications/eve-online/eve-online-warp-to-0-autopilot>

运行这个机器人最简单的方法是在BotLab客户端的"选择机器人"视图中输入上面的地址。

如果你还没有在系统上安装BotLab客户端程序，请按照<https://to.botlab.org/guide/how-to-install-the-botlab-client>的安装指南进行操作。

在运行这个机器人之前，你需要启动EVE Online客户端，不需要进入角色选择界面以外的地方。

当机器人启动时，它会显示以下消息：

> 我在信息面板中没有看到航线。我将在设置航线后开始。

除非你已经在自动导航中设置了航线。

要自定义这个机器人，我们需要更改它的程序代码。程序代码包含在我们提供给BotLab程序的地址后面的文件中。

处理程序代码最简单的方法是使用Elm编辑器：<https://elm-editor.com>

在这个编辑器中，我们可以加载程序代码文件，编辑代码并在遇到问题时获得帮助。

你可以使用Elm编辑器中的"项目"->"从Git仓库加载"对话框来加载位于GitHub上的任何机器人程序代码，例如我们上面使用的代码。

将程序文件加载到Elm编辑器后，选择`Bot.elm`文件在代码编辑器中打开。

这里有一个链接，可以直接将你带入Elm编辑器中的`Bot.elm`文件，自动完成上述导入步骤：
<https://elm-editor.com/?project-state=https%3A%2F%2Fgithub.com%2FViir%2Fbots%2Ftree%2F9567e5b6d7982c4feeed05fef1a24705e8510bfc%2Fimplement%2Fapplications%2Feve-online%2Feve-online-warp-to-0-autopilot&file-path-to-open=Bot.elm>

对程序代码进行更改后，我们可以再次使用Elm编辑器中的"项目"->"导出到ZIP存档"对话框来下载项目中的所有文件及其新内容。
在BotLab客户端中，我们可以直接从该zip存档加载机器人，方法是输入存档的路径作为源。我们不需要解压存档，因为这会自动进行。

现在我们知道如何从编辑器运行程序代码，让我们更改它使其成为我们自己的。

在`Bot.elm`文件的第156行，我们找到了之前在机器人状态消息中看到的文本，用双引号括起来：

![EVE Online自动导航机器人代码在Elm编辑器中](./image/2021-08-29-eve-online-autopilot-bot-code-in-elm-editor-in-space.png)

将双引号之间的文本替换为另一个文本：

```Elm
    case context.readingFromGameClient |> infoPanelRouteFirstMarkerFromReadingFromGameClient of
        Nothing ->
            describeBranch "你好世界！- 我在信息面板中没有看到航线。我将在设置航线后开始。"
                (decideStepWhenInSpaceWaiting context)
```

更改程序代码后，再次使用"导出项目到ZIP存档"对话框获取完整的程序代码，格式为可运行。
运行我们的新版本，我们可以看到机器人的状态文本中反映了这一变化。

### 变得更快

现在你可以生成随机的程序文本序列，并测试哪些更有用。如果你这样做的时间足够长，你会发现一个比任何人以前找到的都更有用的。
但是可能的组合数量太大，无法以这种简单的方式进行。我们需要一种更快地丢弃无用组合的方法。
在本指南的其余部分，我将展示如何加速发现和识别有用组合的过程。

## 观察和检查机器人

机器人程序代码的改进始于观察机器人在环境中的行为。环境可以是合成的、模拟的或实际的游戏客户端。

要了解如何观察和检查机器人的行为，请参阅<https://to.botlab.org/guide/observing-and-inspecting-a-bot>指南。

## 程序代码的整体结构和数据流

在"最简单的自定义机器人"部分，我们更改了`Bot.elm`文件中的代码来自定义机器人。因为我们只做了简单的更改，所以我们可以在不了解程序代码整体结构的情况下完成。我们想要更改的越多，就越能从理解所有内容如何协同工作中受益。

本章解释程序代码的整体结构以及机器人运行时数据的流动方式。

要探索程序的工作原理，我们从你已经有经验的部分开始：可观察的行为。从那里，我们向用户不可见的部分，即实现细节。

在这个过程中，我们还将学习一些机器人开发中使用的基本词汇。了解这种语言将帮助你与其他开发人员交流并在需要时获得帮助。

### 效果

为了使机器人有用，它最终需要以某种方式影响其环境。如果它是一个机器人，它可能会向游戏客户端发送输入。另一方面，情报工具可能会播放声音。我们对运行机器人的这些可观察结果有一个通用名称：我们称之为"效果"。

以下是我们框架中可用的效果列表：

+ 将鼠标光标移动到给定位置。（相对于游戏窗口（更具体地说是该窗口的客户区域））
+ 按下给定的鼠标按钮。
+ 释放给定的鼠标按钮。
+ 按下给定的键盘按键。
+ 释放给定的键盘按键。

这些效果并非特定于EVE Online，这就是为什么我们使用代码模块`Common.EffectOnWindow`中的函数来描述这些效果。

### 事件

为了能够决定哪些效果最有用，机器人需要了解其环境。在我们的情况下，这个环境是游戏客户端。机器人通过事件接收有关游戏客户端的信息。

在编程机器人时，每个效果都源自一个事件。一个事件可以导致零个或多个效果，但机器人不能在没有事件的情况下发出效果。从用户的角度来看，这个约束并不明显，因为用户不知道事件何时发生。但是，了解这个规则有助于理解程序代码的结构。

在我们的EVE Online框架中，事件简化如下：我们自定义的唯一事件是来自游戏客户端的新读取的到达。如果我们使用更通用的框架，我们也会有其他类型的事件。一个例子是当用户更改机器人设置时，这可能随时发生。我们的框架不会在每次机器人设置更改时通知我们。相反，它会在下一次从游戏客户端获取新读取时，将机器人设置和其他上下文信息一起转发给我们。另一个关键的上下文信息是当前时间。时间也只随下一次从游戏客户端获取的新读取一起转发。

### 机器人程序代码结构 - EVE Online框架

为了使开发更容易，我们可以使用EVE Online可用的框架之一。
使用框架是在灵活性和易用性之间的权衡。你可以将其与使用Microsoft Windows而不是构建自定义操作系统进行比较：使用这个平台，我们可以避免学习软件栈的较低层次，如机器编程语言。
在本指南中，我使用从数百名EVE Online用户和开发人员的工作中演变而来的最主流框架。当你查看示例项目时，你会发现许多类型的机器人使用相同的框架。它足够灵活，可以涵盖挖矿、刷怪、交易和任务执行等活动。
此框架的程序代码包含在名为`EveOnline`的子目录中的整体程序代码中。这使得查找框架函数的定义更加容易。
你可以在`Bot.elm`文件中编写所有自定义内容。当你比较组成示例机器人的文件时，你会发现不同的机器人只在`Bot.elm`文件中有所不同。在该代码模块的开头，这些机器人从框架的其他代码模块导入构建块，即`EveOnline.BotFramework`、`EveOnline.BotFrameworkSeparatingMemory`和`EveOnline.ParseUserInterface`。
这三个模块包含数百个构建块来组合你的机器人。

### 入口点 - `botMain`

在每个机器人程序代码的`Bot.elm`文件中，你可以找到一个名为[`botMain`](https://github.com/Viir/bots/blob/9567e5b6d7982c4feeed05fef1a24705e8510bfc/implement/applications/eve-online/eve-online-warp-to-0-autopilot/Bot.elm#L258-L269)的声明。

与该文件中的其他声明相比，`botMain`具有独特的作用。任何其他声明只有在以某种方式被`botMain`引用（直接或间接）时才能影响机器人的行为。由于其独特的作用，我们也将其称为"入口点"。

`botMain`的类型并非特定于EVE Online。其他游戏的机器人使用相同的结构。EVE Online客户端的程序代码使用`EveOnline.BotFrameworkSeparatingMemory`模块中的函数来构建更通用的`botMain`值。我们可以在示例项目中看到这一点，无论是挖矿机器人、刷怪机器人，还是只是监视本地聊天并在敌对玩家进入时提醒用户的监视器。

以下是[自动导航示例机器人代码](https://github.com/Viir/bots/blob/9567e5b6d7982c4feeed05fef1a24705e8510bfc/implement/applications/eve-online/eve-online-warp-to-0-autopilot/Bot.elm#L258-L269)如何使用框架函数配置机器人：

```Elm
botMain : InterfaceToHost.BotConfig State
botMain =
    { init = EveOnline.BotFrameworkSeparatingMemory.initState initBotMemory
    , processEvent =
        EveOnline.BotFrameworkSeparatingMemory.processEvent
            { parseBotSettings = parseBotSettings
            , selectGameClientInstance = always EveOnline.BotFramework.selectGameClientInstanceWithTopmostWindow
            , updateMemoryForNewReadingFromGame = updateMemoryForNewReadingFromGame
            , decideNextStep = autopilotBotDecisionRoot
            , statusTextFromDecisionContext = statusTextFromDecisionContext
            }
    }
```

在上面的代码片段中，我们的程序代码通过使用框架组合来自`Bot.elm`的多个值来组合机器人。

使用`parseBotSettings`字段，我们配置如何将用户的机器人设置字符串解析为结构化表示。机器人设置提供了一种无需更改机器人代码即可自定义机器人行为的方法。我们可以为我们的机器人设置使用任何类型。

### 机器人步骤的数据流

框架将我们机器人的执行结构化为一系列"机器人步骤"。每次来自游戏客户端的新读取完成时，框架执行一个这样的机器人步骤。

进入机器人步骤的信息包含：

+ 来自游戏客户端的读取。
+ 当前时间。
+ 机器人设置，如前所述进行结构化解析。
+ 计划的会话持续时间。

机器人步骤的结果包含：

+ 我们是现在结束会话还是继续？如果我们继续会话，我们向游戏客户端发送的输入序列是什么？
+ 要显示给用户的新状态文本。

在我们在上面的代码片段中提供给框架的五个元素中，它在每个机器人步骤中使用以下三个：

+ `updateMemoryForNewReadingFromGame`：在这里，我们定义了在未来机器人步骤中可能需要记住的任何内容。我们使用这种记忆来记住关于游戏世界的观察，这些观察对于我们在未来做出决策是必要的：哪些小行星带已经耗尽？哪些异常空间包含我们想要避开的危险敌人？这种记忆的另一个应用是跟踪性能统计：在此会话中我们杀死了多少敌人？

+ `decideNextStep`：在这里，我们决定如何继续会话：我们是继续还是结束会话？如果我们继续，我们向游戏客户端发送哪些输入？

+ `statusTextFromDecisionContext`：在这里，我们添加到整个机器人显示的状态文本中。例如，我们扩展此状态文本以显示机器人的性能指标。

`decideNextStep`和`statusTextFromDecisionContext`并行运行。它们不依赖于彼此的输出，但都依赖于`updateMemoryForNewReadingFromGame`的返回值。

下图可视化了单个机器人步骤的数据流：

![EVE Online框架中机器人步骤的数据流](./../image/2021-10-13-data-flow-in-bot-architecture-separating-memory.png)

此图中的箭头说明了框架如何在我们提供的用于组合机器人的函数之间转发数据。

### `parseBotSettings`

每次用户更改机器人设置时，框架都会调用`parseBotSettings`函数。返回类型是一种`Result`，这意味着我们可以决定给定的机器人设置字符串无效并拒绝它。`Err`情况使用`String`类型，我们用它向用户解释给定的机器人设置字符串有什么问题。在大多数情况下，你不想从头开始为用户编写解析和生成错误消息的代码。有一个框架可以基于你指定的设置列表来解析设置字符串。使用这个框架使得添加新设置变得微不足道。在我们的机器人中，我们只需要定义有效设置的列表，如果用户拼写错误设置名称或尝试使用具有不支持值的设置，框架将生成精确的错误消息。

## 编程语言

这里的机器人主要使用Elm编程语言编写。许多机器人还包含一小部分用其他语言（如C#）编写的胶水代码，但由于框架的原因，你甚至不需要阅读这些低级部分。

### Elm简介

学习Elm编程语言的绝佳资源是官方指南：<https://guide.elm-lang.org>

本指南的部分内容特定于Web应用程序，在构建机器人时不太有趣。然而，它也教授了对我们非常有用的基础知识，特别是["核心语言"](https://guide.elm-lang.org/core_language.html)和["类型"](https://guide.elm-lang.org/types/)。
如果你想了解更多细节：[附录](https://guide.elm-lang.org/appendix/function_types.html)涵盖了更高级的主题，帮助理解如何编写应用程序，以及框架是如何构建的。

### 类型

类型是我们通过编程语言获得的重要工具。类型系统允许引擎在我们甚至运行应用程序之前就将注意力吸引到程序代码中的问题上。在示例的程序代码中，你可以在以"type"关键字开头的行上找到许多类型描述。这里有两个例子：

```Elm
type alias DronesWindow =
    { uiNode : UITreeNodeWithDisplayRegion
```

```Elm
type ShipManeuverType
    = ManeuverWarp
    | ManeuverJump
    | ManeuverOrbit
    | ManeuverApproach
```

Elm编程语言指南中有一章["类型"](https://guide.elm-lang.org/types/)，我建议阅读这一章以了解这些语法的含义。如果你在程序代码中遇到令人困惑的"TYPE MISMATCH"错误，这一章也值得一看。在["读取类型"](https://guide.elm-lang.org/types/reading_types.html)部分，你还可以找到一个交互式游乐场，你可以在其中测试Elm语法以揭示有时在程序语法中不可见的类型。

以下是Elm指南中"类型"章节的链接：<https://guide.elm-lang.org/types/>

----

有任何问题吗？[BotLab论坛](https://forum.botlab.org)是结识其他开发人员并获得帮助的地方。