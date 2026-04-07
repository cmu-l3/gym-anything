import email
from email.parser import BytesParser
from email import policy
import glob

files = glob.glob('/compute/babel-u5-24/pranjala/gym_anything_clean/Gym-Anything_for_cmu_super_clean/examples/bluemail_env/assets/emails/ham/ham_*.eml')

uas = {}
x_mailers = {}

for fpath in files:
    with open(fpath, 'rb') as f:
        msg = BytesParser(policy=policy.default).parse(f)
    ua = msg.get('User-Agent')
    xm = msg.get('X-Mailer')
    
    if ua:
        uas[ua] = uas.get(ua, 0) + 1
    if xm:
        x_mailers[xm] = x_mailers.get(xm, 0) + 1

print("User-Agents:")
for k, v in uas.items():
    print(f"{v}: {k}")
    
print("\nX-Mailers:")
for k, v in x_mailers.items():
    print(f"{v}: {k}")
