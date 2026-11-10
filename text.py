import base64

SECRET = "ADYkIT0jNRJEDgpVIwAoFlk6egsTEFkMKjoFURQ="
key = b"Newbie"

# 1. Base64 解码，得到密文字节
cipher = base64.b64decode(SECRET)

# 2. 逐字节和循环密钥异或
result = []
for i in range(len(cipher)):
    k = key[i % len(key)]
    result.append(cipher[i] ^ k)

# 3. 转成字符串输出
flag = bytes(result).decode("utf-8")
print(flag)
