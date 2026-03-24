import os
import shutil
import ast
import json

ROOT_DIR =  os.path.dirname(__file__).split("docker-makefiles")[0]
SAMPLE_FILE = os.path.join(ROOT_DIR, "default-service.definition.json")
INPUT_DIR = os.path.join(ROOT_DIR, "docker-makefiles", "anylog-generic")
INPUT_ENV = os.path.join(INPUT_DIR, "node_configs.env")
OUTPUT_JSON = os.path.join(INPUT_DIR, "node_configs.json")

def read_env():
    configs = []
    comment = ""
    param = None
    value = None
    with open(INPUT_ENV, 'r') as f:
        for line in f.readlines():
            if line.strip():
                if line.startswith("#===") or line.startswith("#---"):
                   pass
                elif line.startswith('#'):
                    comment += line.strip()
                elif '=' in line:
                    param, value = line.split("=", 1)
            if comment and param and value:
                value = value.replace('\n', '').strip()
                if value:
                    try:
                        value = ast.literal_eval(value)
                    except:
                        pass

                value_type = "string"
                if isinstance(value, (int, float)):
                    value_type = "int"

                configs.append({
                    "name": param,
                    "label": comment.replace('#', '').replace('\n', ' ').strip(),
                    "type": value_type,
                    "value": value
                })
                comment = ""
                param = None
                value = None

    return configs

def update_json(configs:list):
    with open(OUTPUT_JSON, 'r') as f:
        file_content = json.load(f)
    file_content["userInput"] = configs

    with open(OUTPUT_JSON, 'w') as f:
        json.dump(file_content, f, indent=2)

def main():
    shutil.copy(SAMPLE_FILE, OUTPUT_JSON)
    configs = read_env()
    update_json(configs=configs)


if __name__ == "__main__":
    main()