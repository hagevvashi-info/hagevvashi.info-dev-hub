package main

import (
    "fmt"
    "math-app/calc" // 「モジュール名/フォルダ名」でインポート
)

func main() {
    var a, b int
    fmt.Print("2つの数字を入力してください（例: 10 20）: ")

    // 標準入力から2つの数値を読み込む
    _, err := fmt.Scan(&a, &b)
    if err != nil {
        fmt.Println("数値を入力してください")
        return
    }

    result := calc.Add(a, b)
    fmt.Printf("合計: %d\n", result)
}
