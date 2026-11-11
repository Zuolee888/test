# AI Agent 简介

AI Agent（人工智能智能体）是一种能够根据目标自主决定部分操作步骤，并调用工具完成任务的 AI 系统。

一个典型的 LLM Agent 通常涉及以下几个部分：

- **大语言模型（LLM）：**理解任务、分析信息，决定下一步操作。
- **规划（Planning）：**将复杂任务拆分成多个步骤，并根据执行情况调整计划。
- **工具调用（Tool Use）：**通过 API、代码执行环境或软件接口完成具体操作。
- **记忆与状态（Memory / State）：**保存执行过程中的信息，必要时读取历史记录或外部知识。

这些模块并不是所有 Agent 都必须具备的独立组件。简单的 Agent 可能只需要模型和工具，复杂系统则可能加入任务规划、长期记忆和多 Agent 协作等能力。

![](C:\Users\zuolee\AppData\Roaming\marktext\images\9114421bb78a60a031a4ef50942a6b57efa87e80.png)

## AI Agent 如何工作

Agent 的核心工作方式是根据任务目标不断执行操作，并利用执行结果决定下一步做什么。

一种常见的实现模式是 **ReAct（Reasoning and Acting）**，即将推理与行动结合起来。

其基本执行流程如下：

1. **接收任务：**用户提出需要完成的目标。
2. **分析任务：**模型判断需要哪些数据、工具和执行步骤。
3. **调用工具：**执行搜索、读取文件、运行代码等操作。
4. **获取结果：**读取工具返回的信息，判断操作是否成功。
5. **继续执行：**根据结果调整后续步骤，直到完成任务或需要人工介入。

![](C:\Users\zuolee\AppData\Roaming\marktext\images\4286da0e8d8ccf47934a35ac8506fe8018a2d666.png)

![](C:\Users\zuolee\AppData\Roaming\marktext\images\cc979a6915f76df4c771b345929550f049826f44.png)

我认为以上agents的知识只是浅浅一笔,在设计agents的时候,半是按照事务运行的常理进行分析和推理,接收到任务要首先分析,分析后做出流程,结合手头现有资料,使用工具,进而分析解答,所以单纯去这样给定义只是书面功夫,真正对于agents的学习在于其行为逻辑的约束和以上种种模块的体系构建中.

![](C:\Users\zuolee\AppData\Roaming\marktext\images\35b35f0a5ff0c9e0cc101fb90247a6bb5073742c.png)

我认为这几个概念可以着重深入讲解一下原理和实现

上下文窗口,推理,幻觉,温度,采样数据,transformer架构,

大模型接口其实就一个通道,输入给他既定格式的内容,他输出既定格式的内容,在这个简易的通道中,产生出的繁杂的agents体系,我觉得最值得研究的就是这些体系的架构原理和实现

因为我们主要关注的是客户端的使用,所以模型的训练的方面我认为我们可以略过,毕竟没有那个客户拿自己的token去训练人家的大模型吧

![](C:\Users\zuolee\AppData\Roaming\marktext\images\c3e5ee43489d276bdffa66626ccb527536900a1e.png)

![](C:\Users\zuolee\AppData\Roaming\marktext\images\490872fed82b1ef98baf166d98d115c925e06b62.png)

![](C:\Users\zuolee\AppData\Roaming\marktext\images\5a741a356f88c6b9baf23c7c675859dc654e768e.png)

![](C:\Users\zuolee\AppData\Roaming\marktext\images\6f5d030e88f083ec8fdf25a281643ea468e63192.png)

为了声明我的想法,我借用[AI Agent 工作原理 | 菜鸟教程](https://www.runoob.com/ai-agent/ai-agent-working-principle.html)这篇文档进行说明,文档使用了Python进行agents的行为模拟,使用既定函数和既定代码来实现,但这也恰恰说明这个体系就是人为的章程,他将agents视为一个既定的程序,实时也的确如此,但是这只是介绍一个流程,我们的目的是进行控制流优化和追求更好的回复结果.

因此,对于整体的流程体系,我们对于他们之间的顺序判定和体系内优化便是重点







## 核心工作原理：Transformer 架构简析

LLM 的惊人能力，离不开其底层核心技术——**Transformer 架构**。不需要深究复杂的数学原理，但可以理解它的核心思想。

想象你要写一篇关于太阳系的文章：

- **通读资料**：你会先看很多相关的书籍和网页。
- **抓住重点**：你会注意到太阳、行星、轨道、引力这些词频繁出现且相互关联。
- **组织语言**：根据你想表达的重点（比如介绍火星），你会选择性地运用之前看到的关于火星大小、颜色、位置等信息，并组织成通顺的句子。

Transformer 的工作方式与此类似，它的核心流程分为三个阶段：

1. **输入处理**：你的话被拆分成词或字（Token），并转换成计算机能理解的数字（向量）。
2. **理解上下文（核心）**：**自注意力机制（Self-Attention）**开始工作。它让模型在处理句子中每一个词时，都能权衡句子中**所有其他词**的重要性。这个过程是**并行**的，速度极快。
3. **生成与循环**：模型基于对所有词的理解，计算出概率分布，预测下一个最可能出现的词。选中并输出这个词后，将其作为新的输入，重复整个过程，直到生成完整回答。



## API 调用与参数设置

要构建 AI Agent，你需要学会如何通过 API 调用 LLM。

等待补充

**mport** os  
**from** openai **import** OpenAI  

# 初始化客户端（核心配置：替换为你的API Key）

client = OpenAI(  
    api_key=os.environ.get('DEEPSEEK_API_KEY'),  # 推荐通过环境变量配置，也可直接写死（不推荐）  
    base_url="https://api.deepseek.com"  # DeepSeek 固定域名  
)  

# 调用对话API

**try**:  
    response = client.chat.completions.create(  
        model="deepseek-v4-flash",  # 指定模型，可选 deepseek-v4-flash / deepseek-v4-pro  
        messages=[  
            {"role": "system", "content": "You are a helpful assistant"},  # 系统角色定义  
            {"role": "user", "content": "Hello"},  # 用户提问  
        ],  
        stream=False  # 非流式输出（一次性返回完整结果）  
    )  
    # 打印回复内容  
    **print**("回复结果：", response.choices[0].message.content)  
**except** Exception **as** e:  
    **print**("调用失败：", str(e))



**from** openai **import** OpenAI  

**def** get_response():  
    client = OpenAI(  
        api_key="sk-xxx",  
        base_url="https://dashscope.aliyuncs.com/compatible-mode/v1",  
    )  

    completion = client.chat.completions.create(  
        model="qwen-plus",  
        messages=[  
            {'role': 'system', 'content': 'You are a helpful assistant.'},  
            {'role': 'user', 'content': '你是谁？'}  
        ],  
        stream=True,  
        stream_options={"include_usage": True}  
    )  

    **for** chunk **in** completion:  
        # chunk 里可能没有 choices 或 delta  
        **if** hasattr(chunk, "choices") **and** len(chunk.choices) > 0:  
            choice = chunk.choices[0]  
            **if** hasattr(choice, "delta") **and** hasattr(choice.delta, "content"):  
                **print**(choice.delta.content, end='', flush=True)  

**if** __name__ == '__main__':  
    get_response()







多模态方面



![](C:\Users\zuolee\AppData\Roaming\marktext\images\d05322903ea2b5ce4c19f8835e00fcbcea9eedf4.png)



落地使用知识

输入输出缓存命中缓存未命中

常用快捷键/或@等等

把最重要的指令放在提示词的**开头或结尾**，中间位置的内容在长上下文中容易被模型"忽视"——这是大模型的已知特性，称为"迷失在中间（Lost in the Middle）"现象。
