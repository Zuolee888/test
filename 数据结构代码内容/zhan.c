#define MAXSIZE 100
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
    if (s->top = -1){
        printf("空的\n");
    }
    else return 0;

}
//Push操作
int push(Stack *s,ElemType e){
    if(s->top>=MAXSIZE-1){
        printf("错误操作\n");
        return 0;
    }
    s->top++;
    s->date[s->top+1] = e;
    return  1;
}
//Pop出栈
 