import ollama
import time

start = time.time()
response = ollama.chat(model="llama3.2:3b",messages=[{"role": "user","content":"reply with exactly one word: attack,defend or magic."}
                                                    ], options={"num_predict": 10},)
elapsed = (time.time() -start) *1000

print(repr(response["message"]["content"]))
print(f"elapsed time: {elapsed:.0f} ms")