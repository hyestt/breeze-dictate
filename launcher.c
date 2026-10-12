/* 小型啟動器：讓 macOS 把「麥克風／輸入監控／輔助使用」授權記在 BreezeDictate.app 名下。
   編譯時由 install.sh 以 -DAPP_DIR 傳入安裝資料夾。 */
#include <stdio.h>
#include <spawn.h>
#include <unistd.h>
#include <sys/wait.h>
extern char **environ;
int main(void) {
  char py[1024];
  snprintf(py, sizeof py, "%s/.venv/bin/python", APP_DIR);
  if (chdir(APP_DIR) != 0) return 1;
  char *argv[] = {py, "-u", "dictate.py", NULL};
  pid_t pid;
  if (posix_spawn(&pid, py, NULL, NULL, argv, environ) != 0) return 1;
  int st;
  waitpid(pid, &st, 0);
  return WIFEXITED(st) ? WEXITSTATUS(st) : 1;
}
