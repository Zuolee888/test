# C 语言逆向分析常用函数详解

> 适用对象：逆向工程入门、CTF Reverse 方向学习
> 内容范围：标准 C 库函数、POSIX 函数、Socket 网络函数、Windows 原生 API、加密编码识别
> 每个函数统一给出：**函数原型、参数个数、头文件、各参数作用、返回值、基础语法示例、逆向提示**

## 阅读说明

1. **参数个数**中写「1+」表示该函数是可变参数函数，至少需要 1 个参数，后面可接任意多个参数。
2. `size_t` 是无符号整数类型（通常等价于 `unsigned int` 或 `unsigned long long`），专门表示大小、长度。
3. `FILE *` 是文件流指针，由 `fopen` 返回，是读写文件的凭证。
4. 示例代码均为最精简的可编译片段，重点展示函数用法，省略了部分错误处理。
5. 头文件中：`<string.h>` 管内存与字符串，`<stdio.h>` 管输入输出，`<stdlib.h>` 管内存分配/转换/系统，`<ctype.h>` 管字符判断。

---

# 第一章 内存与字符串处理函数

## 1.1 memset —— 内存填充（最常用于清零）

- **原型**：`void *memset(void *s, int c, size_t n);`
- **参数个数**：3
- **头文件**：`<string.h>`
- **参数说明**：
  - `s`：目标内存的起始地址（要被填充的缓冲区）。
  - `c`：填充值，虽然类型是 `int`，但实际只取低 8 位，按字节填入；填 `0` 表示清零。
  - `n`：填充的字节数。
- **返回值**：返回第一个参数 `s` 的指针。
- **基础示例**：

```c
#include <string.h>
#include <stdio.h>

int main() {
    char buf[16];
    memset(buf, 0, sizeof(buf));      // 全部清零
    memset(buf, 'A', 8);              // 前 8 字节填成 'A'(0x41)
    printf("%s\n", buf);              // 输出 AAAAAAAA
    return 0;
}
```

- **逆向提示**：第二参数为 0 的 `memset` 几乎都是初始化操作；**第三个参数直接暴露缓冲区大小**，是推算栈变量尺寸的重要依据。

## 1.2 memcpy —— 内存复制

- **原型**：`void *memcpy(void *dest, const void *src, size_t n);`
- **参数个数**：3
- **头文件**：`<string.h>`
- **参数说明**：
  - `dest`：目标地址。
  - `src`：源地址（带 `const` 表示只读，不会被修改）。
  - `n`：复制的字节数。
- **返回值**：返回 `dest`。
- **基础示例**：

```c
#include <string.h>
#include <stdio.h>

int main() {
    char src[] = "hello";
    char dst[16];
    memset(dst, 0, sizeof(dst));
    memcpy(dst, src, 6);          // 连 '\0' 一起复制 6 字节
    printf("%s\n", dst);          // 输出 hello
    return 0;
}
```

- **逆向提示**：可以复制任意二进制数据（结构体、数组、密文），不关心内容是否含 `'\0'`；第三参数可推断结构体/缓冲区长度。**要求源和目标内存不能重叠**，重叠时结果未定义，应使用 `memmove`。

## 1.3 memmove —— 可处理重叠区域的内存复制

- **原型**：`void *memmove(void *dest, const void *src, size_t n);`
- **参数个数**：3
- **头文件**：`<string.h>`
- **参数说明**：与 `memcpy` 完全相同（`dest` 目标、`src` 源、`n` 字节数）。
- **返回值**：返回 `dest`。
- **基础示例**：

```c
#include <string.h>
#include <stdio.h>

int main() {
    char buf[] = "0123456789";
    // 同一缓冲区内部移动，源与目标重叠，memcpy 不可靠，必须用 memmove
    memmove(buf + 2, buf, 8);
    printf("%s\n", buf);          // 输出 0101234567
    return 0;
}
```

- **逆向提示**：功能与 `memcpy` 一致，区别仅在于内部通过临时缓冲或调整复制方向保证重叠安全；IDA 中看到它通常说明程序在操作同一缓冲区内部数据。

## 1.4 memcmp —— 内存比较（密码/密文校验点）

- **原型**：`int memcmp(const void *s1, const void *s2, size_t n);`
- **参数个数**：3
- **头文件**：`<string.h>`
- **参数说明**：
  - `s1`、`s2`：待比较的两块内存。
  - `n`：比较的字节数。
- **返回值**：
  - `0`：前 `n` 字节完全相同；
  - 正数：第一处不同字节处，`s1` 的值大于 `s2`；
  - 负数：第一处不同字节处，`s1` 的值小于 `s2`。
- **基础示例**：

```c
#include <string.h>
#include <stdio.h>

int main() {
    unsigned char a[] = {0x9C, 0xCC, 0x88};
    unsigned char b[] = {0x9C, 0xCC, 0x88};
    if (memcmp(a, b, 3) == 0)
        printf("相同\n");
    else
        printf("不同\n");
    return 0;
}
```

- **逆向提示**：典型的**校验点**，密码、密文、文件魔数、哈希值比对都用它。因为按字节数比较，数据中含 `0x00` 不影响比较，这是它与 `strcmp` 的关键区别。下断点、patch 返回值或前面的条件跳转是常见操作。

## 1.5 strlen —— 求字符串长度

- **原型**：`size_t strlen(const char *s);`
- **参数个数**：1
- **头文件**：`<string.h>`
- **参数说明**：
  - `s`：字符串起始地址，函数从这里一直数到 `'\0'` 为止（`'\0'` 不计入长度）。
- **返回值**：`'\0'` 之前的字符个数。
- **基础示例**：

```c
#include <string.h>
#include <stdio.h>

int main() {
    char s[] = "password";
    printf("%zu\n", strlen(s));   // 输出 8，%zu 专门打印 size_t
    return 0;
}
```

- **逆向提示**：常出现在循环边界判断、输入长度检查处；汇编层面是一个不断递增指针并比对 0 的循环。

## 1.6 strcpy —— 字符串复制（无长度限制）

- **原型**：`char *strcpy(char *dest, const char *src);`
- **参数个数**：2
- **头文件**：`<string.h>`
- **参数说明**：
  - `dest`：目标缓冲区。
  - `src`：源字符串，复制到 `src` 的 `'\0'` 为止（包含 `'\0'`）。
- **返回值**：返回 `dest`。
- **基础示例**：

```c
#include <string.h>
#include <stdio.h>

int main() {
    char src[] = "admin";
    char dst[16];
    strcpy(dst, src);
    printf("%s\n", dst);          // 输出 admin
    return 0;
}
```

- **逆向提示**：**不检查目标缓冲区容量，是经典栈溢出漏洞点**。源过长会直接覆盖栈上后续数据。逆向中看到它要评估源数据是否可控。

## 1.7 strncpy —— 限长字符串复制

- **原型**：`char *strncpy(char *dest, const char *src, size_t n);`
- **参数个数**：3
- **头文件**：`<string.h>`
- **参数说明**：
  - `dest`：目标缓冲区。
  - `src`：源字符串。
  - `n`：最多复制的字节数。
- **返回值**：返回 `dest`。
- **基础示例**：

```c
#include <string.h>
#include <stdio.h>

int main() {
    char src[] = "abcdefghij";
    char dst[8];
    memset(dst, 0, sizeof(dst));
    strncpy(dst, src, sizeof(dst) - 1);  // 最多拷 7 个，留 1 个位置给 '\0'
    printf("%s\n", dst);                  // 输出 abcdefg
    return 0;
}
```

- **逆向提示**：比 `strcpy` 安全，但有一个坑——**当源字符串长度达到 `n` 时，它不会自动补 `'\0'`**，所以工程上通常先清零或手动补结尾。

## 1.8 strcat —— 字符串拼接

- **原型**：`char *strcat(char *dest, const char *src);`
- **参数个数**：2
- **头文件**：`<string.h>`
- **参数说明**：
  - `dest`：目标字符串，必须已有合法内容并以 `'\0'` 结尾；函数找到它的结尾，把 `src` 接在后面。
  - `src`：要追加的字符串。
- **返回值**：返回 `dest`。
- **基础示例**：

```c
#include <string.h>
#include <stdio.h>

int main() {
    char buf[32];
    memset(buf, 0, sizeof(buf));
    strcat(buf, "Hello ");
    strcat(buf, "World");
    printf("%s\n", buf);          // 输出 Hello World
    return 0;
}
```

- **逆向提示**：同样不限长度，目标缓冲区不够大时溢出。

## 1.9 strncat —— 限长字符串拼接

- **原型**：`char *strncat(char *dest, const char *src, size_t n);`
- **参数个数**：3
- **头文件**：`<string.h>`
- **参数说明**：
  - `dest`：目标字符串。
  - `src`：要追加的字符串。
  - `n`：最多追加的字符数；函数**始终会自动补一个 `'\0'`**。
- **返回值**：返回 `dest`。
- **基础示例**：

```c
#include <string.h>
#include <stdio.h>

int main() {
    char buf[16] = "ID:";
    strncat(buf, "20251234567890", 10);
    printf("%s\n", buf);          // 输出 ID:2025123456
    return 0;
}
```

- **逆向提示**：注意第三个参数语义是「最多追加多少字符」，与 `strncpy` 不同，它保证结尾有 `'\0'`。

## 1.10 strcmp —— 字符串比较

- **原型**：`int strcmp(const char *s1, const char *s2);`
- **参数个数**：2
- **头文件**：`<string.h>`
- **参数说明**：
  - `s1`、`s2`：两个字符串，从首字符开始逐个比较，直到出现不同字符或遇到 `'\0'`。
- **返回值**：`0` 表示两串完全相同；非 0 表示不同（负数表示 `s1` 小，正数表示 `s1` 大）。
- **基础示例**：

```c
#include <string.h>
#include <stdio.h>

int main() {
    if (strcmp("admin", "admin") == 0)
        printf("密码正确\n");
    return 0;
}
```

- **逆向提示**：文本密码校验最常见的函数。遇到 `'\0'` 即停止，无法比较含 0 字节的二进制数据。

## 1.11 strncmp —— 限长字符串比较

- **原型**：`int strncmp(const char *s1, const char *s2, size_t n);`
- **参数个数**：3
- **头文件**：`<string.h>`
- **参数说明**：
  - `s1`、`s2`：待比较字符串。
  - `n`：最多比较前 `n` 个字符。
- **返回值**：同 `strcmp`，`0` 表示前 `n` 个字符相同。
- **基础示例**：

```c
#include <string.h>
#include <stdio.h>

int main() {
    if (strncmp("flag{abc}", "flag{xyz}", 5) == 0)
        printf("前 5 个字符相同，都是 flag{\n");
    return 0;
}
```

- **逆向提示**：常用于只检查前缀（如协议头、`flag{` 格式）的场景。

## 1.12 strstr —— 查找子串

- **原型**：`char *strstr(const char *haystack, const char *needle);`
- **参数个数**：2
- **头文件**：`<string.h>`
- **参数说明**：
  - `haystack`：被搜索的主字符串（干草堆）。
  - `needle`：要找的子串（针）。
- **返回值**：找到则返回子串第一次出现位置的指针；找不到返回 `NULL`。
- **基础示例**：

```c
#include <string.h>
#include <stdio.h>

int main() {
    char s[] = "error: invalid input";
    if (strstr(s, "error") != NULL)
        printf("包含错误关键字\n");
    return 0;
}
```

- **逆向提示**：关键字过滤、协议字段匹配处常见。

## 1.13 strchr —— 查找单个字符

- **原型**：`char *strchr(const char *s, int c);`
- **参数个数**：2
- **头文件**：`<string.h>`
- **参数说明**：
  - `s`：被搜索字符串。
  - `c`：要找的字符（`int` 类型但按 `char` 使用）。
- **返回值**：返回该字符第一次出现位置的指针；找不到返回 `NULL`。
- **基础示例**：

```c
#include <string.h>
#include <stdio.h>

int main() {
    char s[] = "name=tom";
    char *p = strchr(s, '=');
    if (p != NULL)
        printf("等号后面的值：%s\n", p + 1);   // 输出 tom
    return 0;
}
```

- **逆向提示**：解析键值对、分隔符时常见。

## 1.14 sprintf —— 格式化输出到字符串（无长度限制）

- **原型**：`int sprintf(char *str, const char *format, ...);`
- **参数个数**：2+（可变参数）
- **头文件**：`<stdio.h>`
- **参数说明**：
  - `str`：输出缓冲区。
  - `format`：格式化字符串，含 `%d`、`%s`、`%x` 等占位符。
  - `...`：与占位符一一对应的实际参数。
- **返回值**：写入的字符个数（不含结尾 `'\0'`）。
- **基础示例**：

```c
#include <stdio.h>

int main() {
    char buf[64];
    int id = 1001;
    sprintf(buf, "user_%d", id);
    printf("%s\n", buf);          // 输出 user_1001
    return 0;
}
```

- **逆向提示**：不限长，存在溢出风险，逆向中注意缓冲区是否够大。

## 1.15 snprintf —— 限长格式化输出

- **原型**：`int snprintf(char *str, size_t size, const char *format, ...);`
- **参数个数**：3+（可变参数）
- **头文件**：`<stdio.h>`
- **参数说明**：
  - `str`：输出缓冲区。
  - `size`：缓冲区总容量，函数最多写入 `size-1` 个字符并自动补 `'\0'`。
  - `format`：格式化字符串。
  - `...`：对应参数。
- **返回值**：**理论上**本应写入的字符数（若返回值 ≥ `size`，说明输出被截断了）。
- **基础示例**：

```c
#include <stdio.h>

int main() {
    char buf[10];
    snprintf(buf, sizeof(buf), "id=%d", 123456);
    printf("%s\n", buf);          // 输出 id=12345（被截断）
    return 0;
}
```

- **逆向提示**：安全版本，第二参数可用来确认缓冲区大小。

## 1.16 sscanf —— 从字符串格式化解析

- **原型**：`int sscanf(const char *s, const char *format, ...);`
- **参数个数**：2+（可变参数）
- **头文件**：`<stdio.h>`
- **参数说明**：
  - `s`：输入字符串。
  - `format`：解析格式，如 `%d`、`%s`、`%x`。
  - `...`：接收结果的变量地址（必须传指针）。
- **返回值**：成功解析并赋值的参数个数。
- **基础示例**：

```c
#include <stdio.h>

int main() {
    char s[] = "tom 20";
    char name[16];
    int age;
    int n = sscanf(s, "%s %d", name, &age);
    printf("解析了 %d 项：%s, %d\n", n, name, age);
    return 0;
}
```

- **逆向提示**：协议解析、配置读取处常见；逆向时按格式串反推输入结构。

## 1.17 atoi —— 字符串转 int

- **原型**：`int atoi(const char *nptr);`
- **参数个数**：1
- **头文件**：`<stdlib.h>`
- **参数说明**：
  - `nptr`：数字字符串，跳过开头空白，从可选正负号开始解析数字，遇到非数字字符停止。
- **返回值**：转换后的 `int` 值；无法转换时返回 `0`。
- **基础示例**：

```c
#include <stdlib.h>
#include <stdio.h>

int main() {
    int n = atoi("123abc");
    printf("%d\n", n);            // 输出 123
    return 0;
}
```

- **逆向提示**：没有错误码，无法区分「输入是 0」还是「转换失败」，严谨场景用 `strtol`。

## 1.18 atol —— 字符串转 long

- **原型**：`long atol(const char *nptr);`
- **参数个数**：1
- **头文件**：`<stdlib.h>`
- **参数说明**：与 `atoi` 相同，唯一区别是返回类型为 `long`（范围更大）。
- **返回值**：转换后的 `long` 值。
- **基础示例**：

```c
#include <stdlib.h>
#include <stdio.h>

int main() {
    long n = atol("100000");
    printf("%ld\n", n);
    return 0;
}
```

- **逆向提示**：注意 32 位程序中 `long` 通常是 4 字节，64 位 Linux 下是 8 字节。

## 1.19 strtol —— 字符串转长整型（带错误检测和进制支持）

- **原型**：`long strtol(const char *nptr, char **endptr, int base);`
- **参数个数**：3
- **头文件**：`<stdlib.h>`
- **参数说明**：
  - `nptr`：待转换字符串。
  - `endptr`：输出参数，指向「解析停止处」的字符地址；不需要可传 `NULL`。
  - `base`：进制，取值 2~36；传 `0` 表示按前缀自动判断（`0x` 开头按 16 进制，`0` 开头按 8 进制，否则按 10 进制）。
- **返回值**：转换结果；越界时返回 `LONG_MAX` 或 `LONG_MIN` 并设置 `errno`。
- **基础示例**：

```c
#include <stdlib.h>
#include <stdio.h>

int main() {
    char *end;
    long n = strtol("0xFF", &end, 16);
    printf("%ld, 剩余字符串：%s\n", n, end);   // 输出 255, 剩余字符串：
    return 0;
}
```

- **逆向提示**：看到 `base=16` 通常是解析十六进制数据；`endptr` 能帮助判断程序是否做了严格校验。

---

# 第二章 标准输入输出与文件函数

## 2.1 printf —— 格式化输出到屏幕

- **原型**：`int printf(const char *format, ...);`
- **参数个数**：1+（可变参数）
- **头文件**：`<stdio.h>`
- **参数说明**：
  - `format`：格式字符串，常用占位符：`%d`(整数)、`%u`(无符号)、`%x`(十六进制)、`%s`(字符串)、`%c`(字符)、`%p`(指针地址)、`%f`(浮点)、`%zu`(size_t)。
  - `...`：与占位符对应的参数。
- **返回值**：实际输出的字符数。
- **基础示例**：

```c
#include <stdio.h>

int main() {
    int score = 95;
    printf("成绩：%d，十六进制：%x\n", score, score);
    return 0;
}
```

- **逆向提示**：格式字符串是理解程序数据含义的线索；逆向中还可借助 `printf` 输出位置判断程序执行到了哪个分支。

## 2.2 fprintf —— 格式化输出到指定文件流

- **原型**：`int fprintf(FILE *stream, const char *format, ...);`
- **参数个数**：2+（可变参数）
- **头文件**：`<stdio.h>`
- **参数说明**：
  - `stream`：目标文件流；传 `stderr` 可输出到标准错误。
  - `format` 及后续参数：同 `printf`。
- **返回值**：输出的字符数。
- **基础示例**：

```c
#include <stdio.h>

int main() {
    fprintf(stderr, "这是一条错误信息\n");
    return 0;
}
```

- **逆向提示**：日志写文件、错误信息输出常用。

## 2.3 puts —— 输出字符串并自动换行

- **原型**：`int puts(const char *s);`
- **参数个数**：1
- **头文件**：`<stdio.h>`
- **参数说明**：
  - `s`：要输出的字符串；函数输出内容后**自动加一个换行符 `'\n'`**。
- **返回值**：成功返回非负数，失败返回 `EOF`（通常为 -1）。
- **基础示例**：

```c
#include <stdio.h>

int main() {
    puts("success");
    puts("fail");
    return 0;
}
```

- **逆向提示**：最简单的结果输出，常跟在校验分支后面，可据此反推哪个分支是校验通过。

## 2.4 fputs —— 输出字符串到文件流（不自动换行）

- **原型**：`int fputs(const char *s, FILE *stream);`
- **参数个数**：2
- **头文件**：`<stdio.h>`
- **参数说明**：
  - `s`：字符串。
  - `stream`：文件流。
- **返回值**：成功返回非负数，失败返回 `EOF`。
- **基础示例**：

```c
#include <stdio.h>

int main() {
    fputs("line1\n", stdout);    // 需要自己写换行符
    return 0;
}
```

- **逆向提示**：与 `puts` 的区别是不自动换行、且可写文件。

## 2.5 putchar —— 输出单个字符

- **原型**：`int putchar(int c);`
- **参数个数**：1
- **头文件**：`<stdio.h>`
- **参数说明**：`c`：要输出的字符（按 `int` 传入，内部转成 `unsigned char`）。
- **返回值**：成功返回该字符，失败返回 `EOF`。
- **基础示例**：

```c
#include <stdio.h>

int main() {
    for (char c = 'A'; c <= 'C'; c++)
        putchar(c);
    putchar('\n');               // 输出 ABC
    return 0;
}
```

## 2.6 fputc —— 输出字符到指定流

- **原型**：`int fputc(int c, FILE *stream);`
- **参数个数**：2
- **头文件**：`<stdio.h>`
- **参数说明**：`c` 字符、`stream` 目标流。
- **返回值**：成功返回该字符，失败返回 `EOF`。
- **基础示例**：

```c
#include <stdio.h>

int main() {
    fputc('X', stdout);
    return 0;
}
```

## 2.7 scanf —— 从键盘格式化读取

- **原型**：`int scanf(const char *format, ...);`
- **参数个数**：1+（可变参数）
- **头文件**：`<stdio.h>`
- **参数说明**：
  - `format`：输入格式，如 `%d`、`%s`。
  - `...`：接收变量的**地址**（必须用 `&`，数组名本身就是地址可省略 `&`）。
- **返回值**：成功读取的项数；读到文件结尾返回 `EOF`。
- **基础示例**：

```c
#include <stdio.h>

int main() {
    int age;
    printf("请输入年龄：");
    scanf("%d", &age);
    printf("你输入了 %d\n", age);
    return 0;
}
```

- **逆向提示**：`%s` 不限制长度，输入过长会溢出，属于危险用法；限长可写成 `%20s`。

## 2.8 fscanf —— 从文件流格式化读取

- **原型**：`int fscanf(FILE *stream, const char *format, ...);`
- **参数个数**：2+（可变参数）
- **头文件**：`<stdio.h>`
- **参数说明**：`stream` 文件流，其余同 `scanf`。
- **返回值**：成功读取项数。
- **基础示例**：

```c
#include <stdio.h>

int main() {
    FILE *fp = fopen("data.txt", "r");
    int n;
    if (fp != NULL) {
        fscanf(fp, "%d", &n);
        fclose(fp);
    }
    return 0;
}
```

## 2.9 fgets —— 读取一行（限长，逆向高频输入函数）

- **原型**：`char *fgets(char *s, int n, FILE *stream);`
- **参数个数**：3
- **头文件**：`<stdio.h>`
- **参数说明**：
  - `s`：接收缓冲区。
  - `n`：最多读取 `n-1` 个字符，自动补 `'\0'`；读到换行符或文件结尾就提前结束，**换行符会被保留**在缓冲区里。
  - `stream`：输入流，读键盘传 `stdin`。
- **返回值**：成功返回 `s`；读到文件结尾或出错返回 `NULL`。
- **基础示例**：

```c
#include <stdio.h>
#include <string.h>

int main() {
    char buf[128];
    fgets(buf, sizeof(buf), stdin);
    int len = strlen(buf);
    if (len > 0 && buf[len - 1] == '\n')
        buf[len - 1] = '\0';     // 手动去掉 fgets 保留的换行符
    printf("你输入了：%s\n", buf);
    return 0;
}
```

- **逆向提示**：安全的输入函数，CTF 题里「fgets + 手动去换行」是固定套路；第二参数直接给出输入长度上限。

## 2.10 gets —— 读取一行（已废弃，极度危险）

- **原型**：`char *gets(char *s);`
- **参数个数**：1
- **头文件**：`<stdio.h>`（C11 标准已从语言中移除）
- **参数说明**：`s`：缓冲区，**没有任何长度参数**，读到换行或 EOF 为止。
- **返回值**：成功返回 `s`，失败返回 `NULL`。
- **基础示例**：

```c
// 仅作认识，现代编译器会警告甚至拒绝编译，实际开发禁止使用
char buf[64];
gets(buf);
```

- **逆向提示**：栈溢出的代名词，看到 `gets` 基本可以确定存在缓冲区溢出；现代题目中若出现，通常是明确的 pwn 考点。

## 2.11 getchar —— 读取单个字符

- **原型**：`int getchar(void);`
- **参数个数**：0
- **头文件**：`<stdio.h>`
- **参数说明**：无参数，从标准输入读一个字符。
- **返回值**：读到的字符（`int` 类型）；文件结尾返回 `EOF`。
- **基础示例**：

```c
#include <stdio.h>

int main() {
    int c = getchar();
    printf("读到字符：%c\n", c);
    return 0;
}
```

## 2.12 fgetc / getc —— 从流读取一个字符

- **原型**：`int fgetc(FILE *stream);` / `int getc(FILE *stream);`
- **参数个数**：1
- **头文件**：`<stdio.h>`
- **参数说明**：`stream`：输入流。
- **返回值**：读到的字符；到结尾返回 `EOF`。
- **基础示例**：

```c
#include <stdio.h>

int main() {
    int c;
    while ((c = fgetc(stdin)) != EOF)
        putchar(c);
    return 0;
}
```

- **逆向提示**：`fgetc` 是函数，`getc` 可能被实现为宏，行为一致。

## 2.13 fopen —— 打开文件

- **原型**：`FILE *fopen(const char *path, const char *mode);`
- **参数个数**：2
- **头文件**：`<stdio.h>`
- **参数说明**：
  - `path`：文件路径。
  - `mode`：打开模式，常用值：
    - `"r"`：只读，文件必须存在；
    - `"w"`：只写，文件不存在则创建，存在则**清空**；
    - `"a"`：追加写；
    - `"rb"`/`"wb"`：二进制模式读/写（Windows 下区分文本与二进制，Linux 下无差别）；
    - `"r+"`：可读可写。
- **返回值**：成功返回 `FILE *`；失败返回 `NULL`。
- **基础示例**：

```c
#include <stdio.h>

int main() {
    FILE *fp = fopen("test.txt", "r");
    if (fp == NULL) {
        printf("打开失败\n");
        return 1;
    }
    fclose(fp);
    return 0;
}
```

- **逆向提示**：程序处理外部文件的起点；模式字符串能说明程序意图（读配置、写日志、追加数据）。

## 2.14 fclose —— 关闭文件

- **原型**：`int fclose(FILE *fp);`
- **参数个数**：1
- **头文件**：`<stdio.h>`
- **参数说明**：`fp`：`fopen` 返回的文件流，关闭时会刷新缓冲区并释放资源。
- **返回值**：成功返回 `0`，失败返回 `EOF`。
- **基础示例**：见 2.13。

## 2.15 fread —— 按块读取二进制数据

- **原型**：`size_t fread(void *ptr, size_t size, size_t nmemb, FILE *stream);`
- **参数个数**：4
- **头文件**：`<stdio.h>`
- **参数说明**：
  - `ptr`：接收数据的缓冲区。
  - `size`：每个元素的大小（字节）。
  - `nmemb`：读取的元素个数；总读取量 = `size × nmemb`。
  - `stream`：文件流。
- **返回值**：实际读到的**完整元素个数**（不是字节数）；小于 `nmemb` 说明读到文件尾或出错。
- **基础示例**：

```c
#include <stdio.h>

int main() {
    FILE *fp = fopen("data.bin", "rb");
    char buf[128];
    if (fp != NULL) {
        size_t n = fread(buf, 1, sizeof(buf), fp);  // 每元素 1 字节，读 128 个
        printf("读到 %zu 字节\n", n);
        fclose(fp);
    }
    return 0;
}
```

- **逆向提示**：识别文件格式解析（图片、自定义二进制格式）的关键函数；常与 `fseek`/`ftell` 配合先求文件大小。

## 2.16 fwrite —— 按块写入二进制数据

- **原型**：`size_t fwrite(const void *ptr, size_t size, size_t nmemb, FILE *stream);`
- **参数个数**：4
- **头文件**：`<stdio.h>`
- **参数说明**：
  - `ptr`：待写入数据。
  - `size`：每元素字节数。
  - `nmemb`：元素个数。
  - `stream`：文件流。
- **返回值**：实际写入的完整元素个数。
- **基础示例**：

```c
#include <stdio.h>

int main() {
    FILE *fp = fopen("out.bin", "wb");
    int data = 0x12345678;
    if (fp != NULL) {
        fwrite(&data, sizeof(int), 1, fp);
        fclose(fp);
    }
    return 0;
}
```

## 2.17 fseek —— 移动文件位置指针

- **原型**：`int fseek(FILE *stream, long offset, int whence);`
- **参数个数**：3
- **头文件**：`<stdio.h>`
- **参数说明**：
  - `stream`：文件流。
  - `offset`：偏移量（字节），可正可负。
  - `whence`：偏移基准，三个常量：
    - `SEEK_SET`：文件开头；
    - `SEEK_CUR`：当前位置；
    - `SEEK_END`：文件末尾。
- **返回值**：成功返回 `0`，失败返回 `-1`。
- **基础示例**：

```c
fseek(fp, 0, SEEK_END);      // 指针移到文件末尾
fseek(fp, 10, SEEK_SET);     // 跳到第 10 字节
```

## 2.18 ftell —— 获取当前文件位置

- **原型**：`long ftell(FILE *stream);`
- **参数个数**：1
- **头文件**：`<stdio.h>`
- **参数说明**：`stream`：文件流。
- **返回值**：当前位置相对文件开头的字节偏移；失败返回 `-1L`。
- **基础示例（求文件大小的经典写法）**：

```c
fseek(fp, 0, SEEK_END);
long size = ftell(fp);       // 末尾位置即文件总字节数
rewind(fp);                  // 回到开头
```

## 2.19 rewind —— 回到文件开头

- **原型**：`void rewind(FILE *stream);`
- **参数个数**：1
- **头文件**：`<stdio.h>`
- **参数说明**：`stream`：文件流，等价于 `fseek(stream, 0, SEEK_SET)`，同时清除错误标志。
- **返回值**：无。
- **基础示例**：见 2.18。

---

# 第三章 堆内存管理函数

## 3.1 malloc —— 堆上分配内存

- **原型**：`void *malloc(size_t size);`
- **参数个数**：1
- **头文件**：`<stdlib.h>`
- **参数说明**：
  - `size`：申请的字节数；**分配的内存内容未初始化，里面是随机垃圾值**。
- **返回值**：成功返回内存起始地址（`void *` 可赋给任意指针类型）；失败返回 `NULL`。
- **基础示例**：

```c
#include <stdlib.h>

int main() {
    int *p = (int *)malloc(10 * sizeof(int));  // 能放 10 个 int
    if (p == NULL)
        return 1;
    p[0] = 100;
    free(p);
    return 0;
}
```

- **逆向提示**：堆题核心函数；返回值必须检查。真实分配大小通常因对齐和块头元数据比申请值略大。

## 3.2 calloc —— 分配并清零

- **原型**：`void *calloc(size_t nmemb, size_t size);`
- **参数个数**：2
- **头文件**：`<stdlib.h>`
- **参数说明**：
  - `nmemb`：元素个数。
  - `size`：每个元素大小；总大小 = `nmemb × size`，分配后**全部字节初始化为 0**。
- **返回值**：成功返回地址，失败返回 `NULL`。
- **基础示例**：

```c
int *p = (int *)calloc(10, sizeof(int));  // 10 个 int，全部为 0
if (p != NULL)
    free(p);
```

- **逆向提示**：与 `malloc` 区别就是自动清零；逆向时看到 `calloc` 可推断程序员希望数组初始为 0。

## 3.3 realloc —— 调整已分配内存大小

- **原型**：`void *realloc(void *ptr, size_t size);`
- **参数个数**：2
- **头文件**：`<stdlib.h>`
- **参数说明**：
  - `ptr`：之前 `malloc`/`calloc`/`realloc` 返回的指针；传 `NULL` 时等价于 `malloc(size)`。
  - `size`：新的大小。
- **返回值**：调整后内存的新地址（**可能与原地址不同，原指针随之失效**）；失败返回 `NULL`，此时原内存仍有效、不会被释放。
- **基础示例**：

```c
int *p = (int *)malloc(4 * sizeof(int));
int *np = (int *)realloc(p, 8 * sizeof(int));
if (np != NULL)
    p = np;                  // 用新指针替换旧指针
free(p);
```

- **逆向提示**：常见错误是直接 `p = realloc(p, ...)`，失败时原指针泄漏。扩容时若原块后面空间不足，会自动搬移并复制旧数据。

## 3.4 free —— 释放堆内存

- **原型**：`void free(void *ptr);`
- **参数个数**：1
- **头文件**：`<stdlib.h>`
- **参数说明**：
  - `ptr`：要释放的堆地址；传 `NULL` 时函数什么都不做。
- **返回值**：无。
- **基础示例**：见 3.1。
- **逆向提示**：释放后该指针成为「野指针」，继续使用就是 UAF（Use After Free）；对同一指针释放两次是 double free，都是 pwn 高频漏洞类型。

## 3.5 C++ 的 new / delete —— 运算符而非函数

- **基础语法**：

```cpp
int *p = new int;             // 分配单个 int
int *arr = new int[10];       // 分配数组
delete p;                     // 释放单个对象
delete[] arr;                 // 释放数组必须用 delete[]
```

- **逆向提示**：底层仍调用 `malloc` 类堆分配，但会额外执行构造函数；IDA 中 `new` 常显示为 `operator new`，注意 `new[]` 与 `delete[]` 必须配对。

---

# 第四章 进程与系统交互函数

## 4.1 system —— 执行系统命令

- **原型**：`int system(const char *command);`
- **参数个数**：1
- **头文件**：`<stdlib.h>`
- **参数说明**：
  - `command`：命令字符串，会交给系统 shell 解释执行（Windows 下是 `cmd.exe`，Linux 下是 `/bin/sh`）。传 `NULL` 不执行命令，只检测 shell 是否可用。
- **返回值**：命令的退出状态；`command` 为 `NULL` 时，非 0 表示 shell 可用。
- **基础示例**：

```c
#include <stdlib.h>

int main() {
    system("notepad.exe");    // Windows 打开记事本
    // system("ls -l");       // Linux 列出目录
    return 0;
}
```

- **逆向提示**：若命令字符串由用户输入拼接而成，可能存在命令注入；逆向中看到 `system` 是行为分析的重点。

## 4.2 exec 函数系列 —— 用新程序替换当前进程（POSIX/Linux）

- **原型与参数个数**：
  - `int execl(const char *path, const char *arg0, ..., (char *)NULL);`（2+，参数列表形式，以 NULL 结尾）
  - `int execv(const char *path, char *const argv[]);`（2，数组形式）
  - `int execvp(const char *file, char *const argv[]);`（2，带 `p` 表示按 PATH 环境变量搜索）
- **头文件**：`<unistd.h>`
- **参数说明**：
  - `path`/`file`：要执行的程序。
  - `arg0`/`argv`：传给新程序的命令行参数，惯例上 `argv[0]` 是程序名。
- **返回值**：成功时**不返回**（当前进程已被替换）；失败返回 `-1`。
- **基础示例**：

```c
#include <unistd.h>

int main() {
    char *argv[] = {"ls", "-l", NULL};
    execvp("ls", argv);       // 成功后当前进程变成 ls
    return 0;                 // 只有失败才会执行到这里
}
```

## 4.3 fork —— 创建子进程（POSIX/Linux）

- **原型**：`pid_t fork(void);`
- **参数个数**：0
- **头文件**：`<unistd.h>`
- **参数说明**：无参数。调用一次，返回两次——父子进程各自继续执行后续代码。
- **返回值**：
  - 父进程中返回子进程的 PID（正数）；
  - 子进程中返回 `0`；
  - 失败返回 `-1`。
- **基础示例**：

```c
#include <unistd.h>
#include <stdio.h>

int main() {
    pid_t pid = fork();
    if (pid == 0)
        puts("我是子进程");
    else if (pid > 0)
        puts("我是父进程");
    return 0;
}
```

## 4.4 exit / _exit —— 终止进程

- **原型**：`void exit(int status);` / `void _exit(int status);`
- **参数个数**：1
- **头文件**：`<stdlib.h>`（exit）/ `<unistd.h>`（_exit）
- **参数说明**：`status`：退出码，`0` 或 `EXIT_SUCCESS` 表示正常结束，非 0 表示异常。
- **返回值**：无。
- **基础示例**：

```c
exit(0);        // 会先刷新 stdio 缓冲区、执行 atexit 注册的函数，再退出
_exit(0);       // 直接陷入内核退出，不刷缓冲（fork 后的子进程常用，避免重复输出）
```

## 4.5 getenv —— 读取环境变量

- **原型**：`char *getenv(const char *name);`
- **参数个数**：1
- **头文件**：`<stdlib.h>`
- **参数说明**：`name`：环境变量名，如 `"PATH"`、`"USERNAME"`。
- **返回值**：对应值字符串的指针；变量不存在返回 `NULL`。
- **基础示例**：

```c
#include <stdlib.h>
#include <stdio.h>

int main() {
    char *user = getenv("USERNAME");
    if (user != NULL)
        printf("当前用户：%s\n", user);
    return 0;
}
```

## 4.6 sleep / Sleep —— 程序休眠

- **原型与参数个数**：
  - POSIX：`unsigned int sleep(unsigned int seconds);`（1 参，单位**秒**，`<unistd.h>`）
  - Windows：`void Sleep(DWORD dwMilliseconds);`（1 参，单位**毫秒**，首字母大写，`<windows.h>`）
- **基础示例**：

```c
// Windows
#include <windows.h>
Sleep(2000);              // 休眠 2 秒

// Linux
#include <unistd.h>
sleep(2);                 // 休眠 2 秒
```

---

# 第五章 随机数与时间函数

## 5.1 rand —— 生成伪随机数

- **原型**：`int rand(void);`
- **参数个数**：0
- **头文件**：`<stdlib.h>`
- **参数说明**：无参数。
- **返回值**：`0` 到 `RAND_MAX`（至少为 32767）之间的整数。
- **基础示例**：

```c
#include <stdlib.h>
#include <stdio.h>

int main() {
    int r = rand() % 100;       // 映射到 0~99
    printf("%d\n", r);
    return 0;
}
```

- **逆向提示**：默认种子固定，不调 `srand` 时每次运行序列完全相同，CTF 中可直接复现；`%` 取模会引入轻微分布偏差。

## 5.2 srand —— 设置随机数种子

- **原型**：`void srand(unsigned int seed);`
- **参数个数**：1
- **头文件**：`<stdlib.h>`
- **参数说明**：`seed`：种子值，相同种子产生相同随机序列。
- **返回值**：无。
- **基础示例**：

```c
#include <stdlib.h>
#include <time.h>

srand((unsigned int)time(NULL));   // 用当前时间做种子，最常见写法
int r = rand();
```

- **逆向提示**：种子若可预测（如时间、固定常量），随机数就可预测；逆向时先找种子来源再复现序列。

## 5.3 time —— 获取日历时间

- **原型**：`time_t time(time_t *t);`
- **参数个数**：1
- **头文件**：`<time.h>`
- **参数说明**：
  - `t`：若非 `NULL`，结果同时写入该地址；传 `NULL` 则只通过返回值拿结果。
- **返回值**：从 1970-01-01 00:00:00 UTC 起经过的秒数；失败返回 `(time_t)-1`。
- **基础示例**：

```c
#include <time.h>
#include <stdio.h>

int main() {
    time_t now = time(NULL);
    printf("%ld\n", (long)now);
    return 0;
}
```

---

# 第六章 字符判断与工具函数

## 6.1 isalpha / isdigit / isalnum —— 字符分类

- **原型**：`int isalpha(int c);` / `int isdigit(int c);` / `int isalnum(int c);`
- **参数个数**：1
- **头文件**：`<ctype.h>`
- **参数说明**：
  - `c`：待判断字符，**要求值为 `unsigned char` 范围或 `EOF`**，直接传负数字符可能越界。
- **返回值**：条件成立返回非 0，不成立返回 `0`。
  - `isalpha`：是否字母；
  - `isdigit`：是否数字 `'0'~'9'`；
  - `isalnum`：是否字母或数字。
- **基础示例**：

```c
#include <ctype.h>

if (isdigit('5'))   // 真
    ;
if (isalpha('Z'))   // 真
    ;
```

## 6.2 toupper / tolower —— 字符大小写转换

- **原型**：`int toupper(int c);` / `int tolower(int c);`
- **参数个数**：1
- **头文件**：`<ctype.h>`
- **参数说明**：`c`：字符；`toupper` 转大写，`tolower` 转小写，非字母字符原样返回。
- **返回值**：转换后的字符。
- **基础示例**：

```c
#include <ctype.h>
#include <stdio.h>

int main() {
    char s[] = "abc";
    for (int i = 0; s[i]; i++)
        s[i] = (char)toupper(s[i]);
    printf("%s\n", s);          // 输出 ABC
    return 0;
}
```

## 6.3 qsort —— 快速排序（通用数组排序）

- **原型**：`void qsort(void *base, size_t nmemb, size_t size, int (*compar)(const void *, const void *));`
- **参数个数**：4
- **头文件**：`<stdlib.h>`
- **参数说明**：
  - `base`：数组起始地址。
  - `nmemb`：元素个数。
  - `size`：每个元素大小。
  - `compar`：比较函数指针，由用户自己写；两个参数 `a`、`b` 指向待比较元素，返回负数表示 `a` 排前面、`0` 表示相等、正数表示 `b` 排前面。
- **返回值**：无。
- **基础示例**：

```c
#include <stdlib.h>
#include <stdio.h>

int cmp_int(const void *a, const void *b) {
    int x = *(const int *)a;
    int y = *(const int *)b;
    return (x > y) - (x < y);   // 升序
}

int main() {
    int arr[] = {5, 2, 9, 1};
    qsort(arr, 4, sizeof(int), cmp_int);
    for (int i = 0; i < 4; i++)
        printf("%d ", arr[i]);  // 输出 1 2 5 9
    return 0;
}
```

- **逆向提示**：看到传入函数指针的四参数调用基本就是 `qsort`；跟入比较函数可确定排序对象和升降序。

## 6.4 assert —— 断言（宏）

- **原型**：`void assert(int expression);`
- **参数个数**：1（宏，不是真正的函数）
- **头文件**：`<assert.h>`
- **参数说明**：`expression`：条件表达式；为假（0）时打印文件名、行号并中止程序。
- **基础示例**：

```c
#include <assert.h>

int divide(int a, int b) {
    assert(b != 0);             // b 为 0 时程序直接中止并报错
    return a / b;
}
```

- **逆向提示**：定义了 `NDEBUG` 宏后所有 `assert` 会被预处理删掉，release 版本中通常不存在。

---

# 第七章 加密与编码的逆向识别

> 加密算法往往没有函数名（静态链接、内联），主要靠**特征常量与代码结构**识别。

## 7.1 常见算法特征速查表

| 算法 | 识别特征 |
|---|---|
| **AES** | 256 字节 S 盒，首项为 `0x63, 0x7C, 0x77, 0x7B...`；明显的轮函数结构（10/12/14 轮） |
| **MD5** | 4 个初始向量 `0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476`；64 轮，输出 16 字节 |
| **SHA-1** | 5 个初始向量，开头同为 `0x67452301`，输出 20 字节 |
| **SHA-256** | 8 个初始哈希值，首个为 `0x6A09E667`；64 个固定 K 常量 |
| **RC4** | 先初始化 0~255 的排列（KSA），再交换生成密钥流（PRGA），出现 256 次循环 |
| **Base64** | 64 字符表 `ABC...XYZabc...xyz012...789+/`，输出长度为 4 的倍数，填充符 `=` |
| **CRC32** | 逆向多项式表首项 `0x00000000, 0x77073096...`（或多项式 `0xEDB88320`） |
| **TEA/XTEA** | 特征魔数 `0x9E3779B9`（黄金分割数），大量左移 4、右移 5 与加减运算 |
| **异或加密** | 单字节/多字节循环异或，结构最简单，CTF 入门题最常见 |

## 7.2 OpenSSL EVP 系列（动态/静态链接常见）

- **典型调用链与参数个数**：

```c
#include <openssl/evp.h>

EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();                      // 0 参，创建上下文
// 5 参：上下文、算法、引擎(通常 NULL)、密钥、IV
EVP_EncryptInit_ex(ctx, EVP_aes_128_cbc(), NULL, key, iv);
// 5 参：上下文、输出缓冲、输出长度(指针)、输入数据、输入长度
EVP_EncryptUpdate(ctx, out, &outlen, in, inlen);
// 3 参：上下文、尾部输出、尾部长度
EVP_EncryptFinal_ex(ctx, out + outlen, &finallen);
EVP_CIPHER_CTX_free(ctx);                                       // 1 参，释放
```

- **逆向提示**：`EVP_aes_128_cbc()` 这类参数直接暴露算法、密钥长度和模式；顺藤摸瓜能找到 key 和 iv。

## 7.3 Windows CryptoAPI：CryptAcquireContext

- **原型**：`BOOL CryptAcquireContext(HCRYPTPROV *phProv, LPCTSTR szContainer, LPCTSTR szProvider, DWORD dwProvType, DWORD dwFlags);`
- **参数个数**：5
- **头文件**：`<wincrypt.h>`，链接 `advapi32.lib`
- **参数说明**：
  - `phProv`：输出，接收加密服务提供者句柄。
  - `szContainer`：密钥容器名，常用 `NULL`。
  - `szProvider`：提供者名，常用 `NULL` 取默认。
  - `dwProvType`：提供者类型，如 `PROV_RSA_FULL`。
  - `dwFlags`：标志，如 `CRYPT_VERIFYCONTEXT`。
- **返回值**：成功返回非 0，失败返回 0。

---

# 第八章 Socket 网络编程函数

> Windows 头文件 `<winsock2.h>`，链接 `ws2_32.lib`，使用前必须先调 `WSAStartup`；
> Linux 头文件 `<sys/socket.h>`、`<netinet/in.h>`、`<arpa/inet.h>`，无需初始化。

## 8.1 socket —— 创建套接字

- **原型**：`int socket(int domain, int type, int protocol);`
- **参数个数**：3
- **参数说明**：
  - `domain`：地址族，`AF_INET` 表示 IPv4，`AF_INET6` 表示 IPv6。
  - `type`：`SOCK_STREAM` 表示 TCP，`SOCK_DGRAM` 表示 UDP。
  - `protocol`：协议，通常填 `0` 由前两个参数决定。
- **返回值**：成功返回套接字描述符（Windows 下叫 `SOCKET`），失败返回 `-1`（Windows 为 `INVALID_SOCKET`）。
- **基础示例**：

```c
int s = socket(AF_INET, SOCK_STREAM, 0);
```

## 8.2 bind —— 绑定地址和端口

- **原型**：`int bind(int sockfd, const struct sockaddr *addr, socklen_t addrlen);`
- **参数个数**：3
- **参数说明**：
  - `sockfd`：套接字。
  - `addr`：地址结构指针，实际常用 `struct sockaddr_in` 强转。
  - `addrlen`：地址结构长度。
- **返回值**：成功 `0`，失败 `-1`。
- **基础示例**：

```c
struct sockaddr_in addr;
addr.sin_family = AF_INET;
addr.sin_port = htons(8080);
addr.sin_addr.s_addr = htonl(INADDR_ANY);
bind(s, (struct sockaddr *)&addr, sizeof(addr));
```

## 8.3 listen —— 进入监听状态（TCP 服务端）

- **原型**：`int listen(int sockfd, int backlog);`
- **参数个数**：2
- **参数说明**：
  - `sockfd`：套接字。
  - `backlog`：等待接受连接的队列最大长度。
- **返回值**：成功 `0`，失败 `-1`。

## 8.4 accept —— 接受一个连接

- **原型**：`int accept(int sockfd, struct sockaddr *addr, socklen_t *addrlen);`
- **参数个数**：3
- **参数说明**：
  - `sockfd`：监听套接字。
  - `addr`：输出对端地址，可传 `NULL`。
  - `addrlen`：输入输出参数，传入结构容量、返回实际长度。
- **返回值**：成功返回**新的**已连接套接字描述符，失败 `-1`。

## 8.5 connect —— 发起连接（TCP 客户端）

- **原型**：`int connect(int sockfd, const struct sockaddr *addr, socklen_t addrlen);`
- **参数个数**：3
- **参数说明**：参数含义同 `bind`，这里地址填的是**服务器**地址。
- **返回值**：成功 `0`，失败 `-1`。

## 8.6 send —— 发送数据

- **原型**：`ssize_t send(int sockfd, const void *buf, size_t len, int flags);`
- **参数个数**：4
- **参数说明**：
  - `sockfd`：已连接套接字。
  - `buf`：待发送数据。
  - `len`：数据长度。
  - `flags`：标志，通常填 `0`。
- **返回值**：实际发送字节数，失败 `-1`。

## 8.7 recv —— 接收数据

- **原型**：`ssize_t recv(int sockfd, void *buf, size_t len, int flags);`
- **参数个数**：4
- **参数说明**：
  - `sockfd`：套接字。
  - `buf`：接收缓冲区。
  - `len`：缓冲区容量。
  - `flags`：通常填 `0`；`MSG_PEEK` 可只偷看不取走。
- **返回值**：实际收到字节数；返回 `0` 表示对方正常关闭连接，失败 `-1`。

## 8.8 htons / htonl / ntohs / ntohl —— 字节序转换

- **原型**：`uint16_t htons(uint16_t x);` 等，均为 **1 个参数**
- **头文件**：`<arpa/inet.h>`（Windows：`<winsock2.h>`）
- **命名含义**：
  - `h` = host（主机字节序），`n` = network（网络字节序，固定大端）；
  - `s` = short（16 位，用于端口），`l` = long（32 位，用于 IP）。
- **基础示例**：

```c
addr.sin_port = htons(8080);              // 端口必须转网络字节序
addr.sin_addr.s_addr = htonl(INADDR_ANY);
```

## 8.9 inet_addr —— 点分十进制 IP 转整数

- **原型**：`in_addr_t inet_addr(const char *cp);`
- **参数个数**：1
- **参数说明**：`cp`：如 `"192.168.1.1"` 的字符串。
- **返回值**：网络字节序的 32 位地址；非法字符串返回 `INADDR_NONE`。
- **基础示例**：

```c
addr.sin_addr.s_addr = inet_addr("127.0.0.1");
```

## 8.10 WSAStartup —— Windows 套接字初始化

- **原型**：`int WSAStartup(WORD wVersionRequested, LPWSADATA lpWSAData);`
- **参数个数**：2
- **头文件**：`<winsock2.h>`
- **参数说明**：
  - `wVersionRequested`：请求的版本，常用 `MAKEWORD(2, 2)` 表示 2.2 版。
  - `lpWSAData`：输出参数，指向 `WSADATA` 结构接收系统信息。
- **返回值**：成功返回 `0`；程序结束时应配对调用 `WSACleanup()`。
- **基础示例**：

```c
#include <winsock2.h>

WSADATA wsa;
if (WSAStartup(MAKEWORD(2, 2), &wsa) != 0)
    return 1;
// ... 网络操作 ...
WSACleanup();
```

---

# 第九章 Windows 原生 API

## 9.1 LoadLibrary —— 动态加载 DLL

- **原型**：`HMODULE LoadLibraryA(LPCSTR lpLibFileName);`（另有宽字符版 `LoadLibraryW`）
- **参数个数**：1
- **头文件**：`<windows.h>`
- **参数说明**：`lpLibFileName`：DLL 路径或名称，如 `"kernel32.dll"`。
- **返回值**：成功返回模块句柄 `HMODULE`，失败返回 `NULL`。
- **基础示例**：

```c
#include <windows.h>

HMODULE h = LoadLibraryA("user32.dll");
if (h != NULL)
    FreeLibrary(h);
```

- **逆向提示**：配合 `GetProcAddress` 动态解析 API，可隐藏导入表，恶意软件常用。

## 9.2 GetProcAddress —— 获取导出函数地址

- **原型**：`FARPROC GetProcAddress(HMODULE hModule, LPCSTR lpProcName);`
- **参数个数**：2
- **头文件**：`<windows.h>`
- **参数说明**：
  - `hModule`：`LoadLibrary` 返回的模块句柄。
  - `lpProcName`：函数名字符串；也可传 `MAKEINTRESOURCEA(序号)` 按序号导出。
- **返回值**：函数地址，调用前需强转为对应函数指针类型；失败返回 `NULL`。
- **基础示例**：

```c
#include <windows.h>

typedef int (WINAPI *MsgBoxA)(HWND, LPCSTR, LPCSTR, UINT);
HMODULE h = LoadLibraryA("user32.dll");
MsgBoxA fn = (MsgBoxA)GetProcAddress(h, "MessageBoxA");
fn(NULL, "hello", "tip", MB_OK);
FreeLibrary(h);
```

## 9.3 VirtualAlloc —— 虚拟内存分配

- **原型**：`LPVOID VirtualAlloc(LPVOID lpAddress, SIZE_T dwSize, DWORD flAllocationType, DWORD flProtect);`
- **参数个数**：4
- **头文件**：`<windows.h>`
- **参数说明**：
  - `lpAddress`：期望起始地址，通常传 `NULL` 由系统决定。
  - `dwSize`：分配大小。
  - `flAllocationType`：分配类型，常用 `MEM_COMMIT | MEM_RESERVE`（保留并提交）。
  - `flProtect`：内存保护属性，如 `PAGE_READWRITE`、`PAGE_EXECUTE_READWRITE`。
- **返回值**：成功返回内存地址，失败 `NULL`。
- **基础示例**：

```c
char *buf = VirtualAlloc(NULL, 4096, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
if (buf != NULL)
    VirtualFree(buf, 0, MEM_RELEASE);
```

- **逆向提示**：申请带 `PAGE_EXECUTE_READWRITE`（可执行）属性的内存，往往是为了存放 shellcode，逆向中要高度关注。

## 9.4 VirtualProtect —— 修改内存保护属性

- **原型**：`BOOL VirtualProtect(LPVOID lpAddress, SIZE_T dwSize, DWORD flNewProtect, PDWORD lpflOldProtect);`
- **参数个数**：4
- **头文件**：`<windows.h>`
- **参数说明**：
  - `lpAddress`：目标内存起始地址。
  - `dwSize`：修改大小。
  - `flNewProtect`：新属性，如 `PAGE_EXECUTE_READWRITE`。
  - `lpflOldProtect`：输出旧属性，必须提供有效指针。
- **返回值**：成功非 0，失败 0。
- **逆向提示**：自修改代码、给 .text 段开执行写权限时常见。

## 9.5 CreateFile —— 打开/创建文件或设备

- **原型**：`HANDLE CreateFileA(LPCSTR lpFileName, DWORD dwDesiredAccess, DWORD dwShareMode, LPSECURITY_ATTRIBUTES lpSecurityAttributes, DWORD dwCreationDisposition, DWORD dwFlagsAndAttributes, HANDLE hTemplateFile);`
- **参数个数**：7
- **头文件**：`<windows.h>`
- **参数说明**：
  - `lpFileName`：文件/设备名。
  - `dwDesiredAccess`：访问权限，`GENERIC_READ`/`GENERIC_WRITE`。
  - `dwShareMode`：共享模式，常填 `0` 独占或 `FILE_SHARE_READ`。
  - `lpSecurityAttributes`：安全属性，常填 `NULL`。
  - `dwCreationDisposition`：`OPEN_EXISTING`（打开已有）、`CREATE_ALWAYS`（总是创建）等。
  - `dwFlagsAndAttributes`：文件属性，常填 `FILE_ATTRIBUTE_NORMAL`。
  - `hTemplateFile`：模板句柄，常填 `NULL`。
- **返回值**：成功返回句柄，失败返回 `INVALID_HANDLE_VALUE`；用完调 `CloseHandle`。

## 9.6 ReadFile —— 读文件/设备

- **原型**：`BOOL ReadFile(HANDLE hFile, LPVOID lpBuffer, DWORD nNumberOfBytesToRead, LPDWORD lpNumberOfBytesRead, LPOVERLAPPED lpOverlapped);`
- **参数个数**：5
- **头文件**：`<windows.h>`
- **参数说明**：
  - `hFile`：`CreateFile` 返回的句柄。
  - `lpBuffer`：接收缓冲区。
  - `nNumberOfBytesToRead`：想读的字节数。
  - `lpNumberOfBytesRead`：输出实际读到的字节数。
  - `lpOverlapped`：异步 IO 用，同步模式填 `NULL`。
- **返回值**：成功非 0，失败 0。

## 9.7 WriteFile —— 写文件/设备

- **原型**：`BOOL WriteFile(HANDLE hFile, LPCVOID lpBuffer, DWORD nNumberOfBytesToWrite, LPDWORD lpNumberOfBytesWritten, LPOVERLAPPED lpOverlapped);`
- **参数个数**：5
- **头文件**：`<windows.h>`
- **参数说明**：与 `ReadFile` 对应，`lpBuffer` 为待写数据，`lpNumberOfBytesWritten` 输出实际写入字节数。
- **返回值**：成功非 0，失败 0。
- **基础示例（9.5~9.7 连贯用法）**：

```c
HANDLE h = CreateFileA("a.txt", GENERIC_WRITE, 0, NULL,
                       CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
if (h != INVALID_HANDLE_VALUE) {
    DWORD written;
    WriteFile(h, "hello", 5, &written, NULL);
    CloseHandle(h);
}
```

## 9.8 CreateProcess —— 创建新进程

- **原型**：`BOOL CreateProcessA(LPCSTR lpApplicationName, LPSTR lpCommandLine, LPSECURITY_ATTRIBUTES lpProcessAttributes, LPSECURITY_ATTRIBUTES lpThreadAttributes, BOOL bInheritHandles, DWORD dwCreationFlags, LPVOID lpEnvironment, LPCSTR lpCurrentDirectory, LPSTARTUPINFOA lpStartupInfo, LPPROCESS_INFORMATION lpProcessInformation);`
- **参数个数**：10
- **头文件**：`<windows.h>`
- **参数说明**：
  - `lpApplicationName`：程序路径，可填 `NULL` 由命令行决定。
  - `lpCommandLine`：完整命令行（注意是可写缓冲区，不能传字符串字面量）。
  - `lpProcessAttributes`/`lpThreadAttributes`：安全属性，常填 `NULL`。
  - `bInheritHandles`：是否继承父进程句柄，常填 `FALSE`。
  - `dwCreationFlags`：创建标志，如 `CREATE_SUSPENDED`（挂起创建，注入常用）。
  - `lpEnvironment`：环境块，`NULL` 表示继承。
  - `lpCurrentDirectory`：工作目录，`NULL` 表示继承。
  - `lpStartupInfo`：启动信息结构，必须先初始化。
  - `lpProcessInformation`：输出进程/线程句柄与 ID。
- **返回值**：成功非 0，失败 0。

## 9.9 RegOpenKeyEx —— 打开注册表键

- **原型**：`LSTATUS RegOpenKeyExA(HKEY hKey, LPCSTR lpSubKey, DWORD ulOptions, REGSAM samDesired, PHKEY phkResult);`
- **参数个数**：5
- **头文件**：`<windows.h>`
- **参数说明**：
  - `hKey`：根键，如 `HKEY_LOCAL_MACHINE`、`HKEY_CURRENT_USER`。
  - `lpSubKey`：子键路径。
  - `ulOptions`：保留，填 `0`。
  - `samDesired`：期望权限，如 `KEY_READ`、`KEY_WRITE`。
  - `phkResult`：输出打开的键句柄，用完调 `RegCloseKey`。
- **返回值**：`ERROR_SUCCESS`（0）表示成功。

---

# 附录

## 附录 A：str 系与 mem 系的核心区别

| 对比项 | str 系列（strcmp/strcpy/strlen） | mem 系列（memcmp/memcpy/memset） |
|---|---|---|
| 停止条件 | 遇到 `'\0'` 停止 | 严格按参数 `n` 处理，不关心 `'\0'` |
| 适用数据 | 文本字符串 | 任意二进制数据（密文、结构体、图片） |
| 长度参数 | 无（或仅作上限） | 必须显式给出字节数 |

## 附录 B：危险函数与安全替代对照

| 危险函数 | 风险 | 推荐替代 |
|---|---|---|
| `gets` | 无长度限制，必然可能溢出 | `fgets` |
| `strcpy` | 不检查目标容量 | `strncpy`（并保证结尾） |
| `strcat` | 同上 | `strncat` |
| `sprintf` | 不检查输出长度 | `snprintf` |
| `scanf("%s")` | 不限长 | `scanf("%20s")` 或 `fgets` |
| `rand` | 伪随机可预测 | 安全场景用系统级随机（`BCryptGenRandom` 等） |

## 附录 C：逆向分析速查——看到函数第一反应

| 函数 | 第一反应 |
|---|---|
| `memset(...,0,...)` | 初始化，第三参数是缓冲区大小 |
| `fgets` / `scanf` / `gets` | 输入点，追踪数据从这里进入 |
| `memcmp` / `strcmp` | 校验点，重点分析比较对象与分支 |
| `fopen` / `CreateFile` | 文件操作，判断读还是写 |
| `fread` / `ReadFile` | 数据加载，可能是文件格式解析 |
| `malloc` / `free` | 堆操作，关注 UAF、double free |
| `system` / `CreateProcess` | 命令/进程行为，检查注入 |
| `rand` / `srand` | 找种子，判断随机序列能否复现 |
| `LoadLibrary` / `GetProcAddress` | 动态解析，跟出真实 API |
| `VirtualAlloc` + 可执行属性 | 可能存放 shellcode |
| 未知常量 `0x9E3779B9` | TEA 系列；`0x63,0x7C...` 是 AES；Base64 字符表是编码 |

---

**学习建议**：优先熟练第一章（内存/字符串）和第二章（输入输出），它们覆盖入门逆向题的绝大多数调用；再结合附录 C 建立「函数 → 程序行为」的条件反射，之后遇到堆、网络、加密类题目时逐章扩展即可。
