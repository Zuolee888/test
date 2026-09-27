#include<stdio.h>
#define MAXSIZE 100
typedef int ElemType;

typedef struct {
    ElemType date[MAXSIZE];
    int length;
}SeqList;
//顺序表初始化initialize初始化
void initList (SeqList *L){
    L->length = 0;
}

//尾部添加元素
int appendElem(SeqList *L, ElemType e){
    if (L->length>=MAXSIZE){
        printf("顺序表已满\n");
        return 0;
    }
    L->date[L->length] = e;
    L->length++;
    return 1;

}

//遍历
void listElem(SeqList *L ){
    for (int i = 0 ;i<L->length;i++){
        printf("%d",L->date[i]);
    }
    printf("\n");
}

//插入元素
int insertElem(SeqList *L ,int pos,ElemType e){
    if (L->length>=MAXSIZE){
        printf("顺序表已满\n");
    }
    if(pos>L->length){
        printf("位置错误");
    }
    for (int i =L->length-1;i>=pos -1;i--){
        L->date[i+1] = L->date[i];
    }
    L->date[pos-1] = e;
    L->length++;
}

//删除元素
int deleteElem(SeqList *L ,int pos,ElemType* e ){
    *e = L->date[pos-1];
    for (int i = pos -1 ;i<L->length;i++){
        L->date[i-1] = L->date[i];

    }
    printf("已删除%d\n",*e);
    L->length--;
    return 1;
}
//测试
int main(int argc , char const *argv[]){
    SeqList list ;
    initList(&list);
    printf("初始化成功,目前占用长度%d\n",list.length);
    printf("目前占用内存%zu字节\n",sizeof(list.date));
    appendElem(&list ,100);
    appendElem(&list ,200);
    appendElem(&list ,300);
    appendElem(&list ,400);
    printf("已添加元素%d,当前长度为%d\n",list.date[0],list.length);
    printf("遍历\n");
    listElem(&list);
    printf("插入后遍历\n");
    insertElem(&list,2,100);
    listElem(&list);
    printf("删除值\n");
    ElemType delDate;
    deleteElem(&list,3,&delDate);
    return 0 ;
}
//动态内存分配初始化
//待完善

