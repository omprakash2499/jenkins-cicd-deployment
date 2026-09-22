"""Submit this repository's release script to one SSM instance and verify completion."""
import base64
import json
import os
import re
import shlex
import subprocess
import time
from pathlib import Path

def main():
    instance = os.environ['INSTANCE_ID']
    region = os.environ['AWS_REGION']
    image = os.environ['DEPLOY_IMAGE']
    if not re.fullmatch(r'i-[a-f0-9]{8,17}', instance):
        raise ValueError('Invalid instance ID')
    if not re.fullmatch(r'[a-z]{2}-[a-z]+-[0-9]+', region):
        raise ValueError('Invalid region')
    if not re.fullmatch(r'[0-9]{12}\.dkr\.ecr\.' + re.escape(region) + r'\.amazonaws\.com/[a-z0-9/_-]+@sha256:[a-f0-9]{64}', image):
        raise ValueError('Expected an ECR digest in the selected region')
    encoded = base64.b64encode(Path(__file__).with_name('release.sh').read_bytes()).decode()
    command = 'script=$(mktemp); trap \'rm -f "$script"\' EXIT; printf %s ' + shlex.quote(encoded) + ' | base64 -d > "$script"; bash "$script" ' + shlex.quote(image) + ' ' + shlex.quote(region)
    def aws(*args):
        result = subprocess.run(['aws', '--region', region, '--output', 'json', 'ssm', *args], text=True, capture_output=True, timeout=45)
        if result.returncode:
            raise RuntimeError(result.stderr.strip())
        return json.loads(result.stdout)
    response = aws('send-command', '--instance-ids', instance, '--document-name', 'AWS-RunShellScript', '--timeout-seconds', '60', '--parameters', json.dumps({'commands': [command], 'executionTimeout': ['600']}))
    command_id = response['Command']['CommandId']
    print('SSM command:', command_id, flush=True)
    for _ in range(150):
        time.sleep(5)
        try:
            status = aws('get-command-invocation', '--command-id', command_id, '--instance-id', instance)
        except RuntimeError as error:
            if 'InvocationDoesNotExist' in str(error):
                continue
            raise
        if status['Status'] in ('Pending', 'InProgress', 'Delayed', 'Cancelling'):
            continue
        print(status.get('StandardOutputContent', ''))
        print(status.get('StandardErrorContent', ''))
        Path('deployment-result.json').write_text(json.dumps(status, indent=2))
        if status['Status'] != 'Success':
            raise RuntimeError('Deployment failed: ' + status['Status'])
        return
    raise TimeoutError('No terminal status. Inspect this SSM command before retrying: ' + command_id)

if __name__ == '__main__':
    main()
