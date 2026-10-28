import os,pathlib,subprocess,tempfile,sys
script=pathlib.Path(__file__).resolve().parent.parent/'install.sh'
archive=str(pathlib.Path(sys.argv[1]).resolve())
with tempfile.TemporaryDirectory() as tmp:
 root=pathlib.Path(tmp); mock=root/'bin'; mock.mkdir(); home=root/'home'; home.mkdir()
 curl=mock/'curl'; curl.write_text('#!/bin/bash\ncp "$CONVY_TEST_ARCHIVE" "$7"\n'); curl.chmod(0o755)
 launcher=mock/'open'; launcher.write_text('#!/bin/bash\nexit 0\n'); launcher.chmod(0o755)
 running=mock/'pgrep'; running.write_text('#!/bin/bash\nexit "${CONVY_TEST_RUNNING:-1}"\n'); running.chmod(0o755)
 env={**os.environ,'CONVY_TEST_ARCHIVE':archive,'HOME':str(home),'PATH':str(mock)+':'+os.environ['PATH']}
 result=subprocess.run(['bash',str(script)],env=env,text=True,capture_output=True)
 assert result.returncode==0,(result.stdout,result.stderr)
 assert (home/'Applications/Convy.app/Contents/MacOS/Convy').exists()
 result=subprocess.run(['bash',str(script)],env=env,text=True,capture_output=True)
 assert result.returncode==0,(result.stdout,result.stderr)
 assert list((home/'Applications').glob('.Convy-update.*/Previous.app/Contents/MacOS/Convy'))
 result=subprocess.run(['bash',str(script)],env={**env,'CONVY_TEST_RUNNING':'0'},text=True,capture_output=True)
 assert result.returncode!=0 and 'Quit Convy' in result.stderr
 import shutil
 shutil.rmtree(home/'Applications/Convy.app')
 lock=home/'Applications/Convy.app.update-lock'; lock.mkdir()
 result=subprocess.run(['bash',str(script)],env=env,text=True,capture_output=True)
 assert result.returncode!=0 and not (home/'Applications/Convy.app').exists()
 lock.rmdir()
 curl.write_text('#!/bin/bash\nprintf broken > "$7"\n')
 result=subprocess.run(['bash',str(script)],env=env,text=True,capture_output=True)
 assert result.returncode!=0 and not (home/'Applications/Convy.app').exists()
 print('PASS: install, upgrade with backup, running-app/lock protection, corrupted download rejection')
