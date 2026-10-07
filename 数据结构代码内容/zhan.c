#define MAXSIZE 100
#include<stdio.h>
typedef int ElemType ;
typedef struct {
    ElemType date[MAXSIZE];
    int top ;
}Stack;
//初始化
void initStack(Stack *s){
    s->top = -1;
} 
//判断是否为空
int isEmpty(Stack *s){
    return s->top == -1;
}
//Push操作
int push(Stack *s,ElemType e){
    if(s->top>=MAXSIZE-1){
        printf("错误操作\n");
        return 0;
    }
    s->top++;
    s->date[s->top] = e;
    return  1;
}
//Pop出栈
ElemType pop(Stack *s,ElemType *e){
    if (s->top ==-1){
        printf("空的\n");
        return 0;
    }
    *e = s->date[s->top ];
    s->top--;
    return *e;
}
//测试
int main(void) {
    Stack zhan;
    int e;

    initStack(&zhan);

    if (isEmpty(&zhan)) {
        printf("栈为空\n");
    }

    if (push(&zhan, 100)) {
        printf("入栈成功\n");
    }

    if (pop(&zhan, &e)) {
        printf("出栈元素：%d\n", e);
    }

    return 0;
}