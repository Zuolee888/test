#include <stdio.h>
typedef int Elemtype;
typedef struct node{
    Elemtype data;
    struct node *next;
}Node;
//初始化
Node* initList(){
    Node *head = (Node*)malloc(sizeof(Node));
    head->data = 0;
    head->next = NULL;
    return head;
}
//测试
int main(){
    Node *list = initList();
    
    return 1;
}