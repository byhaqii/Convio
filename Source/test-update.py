import os
import pathlib
import subprocess
import tempfile

helper = pathlib.Path(__file__).resolve().parent / 'update-app.sh'
with tempfile.TemporaryDirectory() as temporary:
    root = pathlib.Path(temporary)
    mock = root / 'bin'
    mock.mkdir()
    launcher = mock / 'open'
    launcher.write_text('#!/bin/bash\nexit "${LAUNCH_RESULT:-0}"\n')
    launcher.chmod(0o755)
    mover = mock / 'mv'
    mover.write_text('#!/bin/bash\nif [[ "${FAIL_MOVE:-}" == "$1" ]]; then exit 1; fi\nexec /bin/mv "$@"\n')
    mover.chmod(0o755)
    env = {**os.environ, 'PATH': str(mock) + ':' + os.environ['PATH']}
    for scenario in ['success', 'launch-failure', 'move-failure', 'locked']:
        case = root / scenario
        case.mkdir()
        installed = case / 'Convio.app'
        installed.mkdir()
        (installed / 'version').write_text('old')
        work = case / '.Convio-update-test'
        work.mkdir()
        staged = work / 'Convio.app'
        staged.mkdir()
        (staged / 'version').write_text('new')
        if scenario == 'locked':
            pathlib.Path(str(installed) + '.update-lock').mkdir()
        result = subprocess.run(['bash', str(helper), '0', str(installed), str(staged)],
                                env={**env, 'LAUNCH_RESULT': '1' if scenario == 'launch-failure' else '0',
                                     'FAIL_MOVE': str(staged) if scenario == 'move-failure' else ''},
                                capture_output=True, text=True)
        assert (installed / 'version').read_text() == ('new' if scenario == 'success' else 'old'), result.stderr
        assert (result.returncode == 0) == (scenario == 'success'), result.stderr
        if scenario == 'success':
            assert (work / 'Previous.app/version').read_text() == 'old'
    print('PASS: app replacement, backup, rollback after failed move/relaunch, install lock')
