import base64
str = "991YiZWOz81ZhFjZfJXdwk3X1k2XzIXZIt3ZhxmZ"
str2 = str[::-1]

print (base64.b64decode(str2))