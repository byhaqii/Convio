import os,pathlib,subprocess,tempfile,sys
script=pathlib.Path(__file__).resolve().parent.parent/'install.sh'
archive=str(pathlib.Path(sys.argv[1]).resolve())
with tempfile.TemporaryDirectory() as tmp:
 root=pathlib.Path(tmp); mock=root/'bin'; mock.mkdir(); home=root/'home'; home.mkdir()
 curl=mock/'curl'; curl.write_text('#!/bin/bash\ncp "$CONVIO_TEST_ARCHIVE" "$7"\n'); curl.chmod(0o755)
 launcher=mock/'open'; launcher.write_text('#!/bin/bash\nexit 0\n'); launcher.chmod(0o755)
 running=mock/'pgrep'; running.write_text('#!/bin/bash\nexit "${CONVIO_TEST_RUNNING:-1}"\n'); running.chmod(0o755)
 env={**os.environ,'CONVIO_TEST_ARCHIVE':archive,'HOME':str(home),'PATH':str(mock)+':'+os.environ['PATH']}
 result=subprocess.run(['bash',str(script)],env=env,text=True,capture_output=True)
 assert result.returncode==0,(result.stdout,result.stderr)
 assert (home/'Applications/Convio.app/Contents/MacOS/Convio').exists()
 result=subprocess.run(['bash',str(script)],env=env,text=True,capture_output=True)
 assert result.returncode==0,(result.stdout,result.stderr)
 assert list((home/'Applications').glob('.Convio-update.*/Previous.app/Contents/MacOS/Convio'))
 result=subprocess.run(['bash',str(script)],env={**env,'CONVIO_TEST_RUNNING':'0'},text=True,capture_output=True)
 assert result.returncode!=0 and 'Quit Convio' in result.stderr
 import shutil
 shutil.rmtree(home/'Applications/Convio.app')
 lock=home/'Applications/Convio.app.update-lock'; lock.mkdir()
 result=subprocess.run(['bash',str(script)],env=env,text=True,capture_output=True)
 assert result.returncode!=0 and not (home/'Applications/Convio.app').exists()
 lock.rmdir()
 curl.write_text('#!/bin/bash\nprintf broken > "$7"\n')
 result=subprocess.run(['bash',str(script)],env=env,text=True,capture_output=True)
 assert result.returncode!=0 and not (home/'Applications/Convio.app').exists()
 print('PASS: install, upgrade with backup, running-app/lock protection, corrupted download rejection')
