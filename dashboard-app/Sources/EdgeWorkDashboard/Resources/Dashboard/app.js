const bridge = window.webkit?.messageHandlers?.edge;
const post = (payload) => bridge?.postMessage(payload);

document.addEventListener('click', (event) => {
  const workspace = event.target.closest('[data-workspace]');
  if (workspace) {
    activateWorkspace(workspace.dataset.workspace);
    post({ type: 'action', action: 'workspace.select', workspace: workspace.dataset.workspace });
    return;
  }
  const folderMenu = event.target.closest('[data-folder-menu]');
  if (folderMenu) {
    openFolderActions(folderMenu.dataset.folderMenu);
    return;
  }
  const folderPrimary = event.target.closest('[data-folder-primary]');
  if (folderPrimary) {
    runFolderPrimaryAction(folderPrimary.dataset.folderPrimary);
    return;
  }
  const element = event.target.closest('[data-action]');
  if (!element) return;
  const payload = { type: 'action', action: element.dataset.action };
  if (element.dataset.folder) payload.folder = element.dataset.folder;
  if (element.dataset.application) payload.application = element.dataset.application;
  post(payload);
  if (element.dataset.action?.startsWith('folder.open-')) closeFolderActions();
});

const controlsBackdrop = document.querySelector('#controls-backdrop');
const quitArm = document.querySelector('#quit-arm');
const quitConfirm = document.querySelector('#quit-confirm');
document.querySelector('#controls-open').addEventListener('click', () => {
  quitConfirm.hidden = true;
  quitArm.hidden = false;
  controlsBackdrop.hidden = false;
});
document.querySelector('#controls-close').addEventListener('click', () => {
  controlsBackdrop.hidden = true;
});
quitArm.addEventListener('click', () => {
  quitArm.hidden = true;
  quitConfirm.hidden = false;
});

let dashboardWorkspaces = [];
let dashboardFolders = [];
let dashboardApplications = [];
let activeWorkspaceID = null;

const folderActionsBackdrop = document.querySelector('#folder-actions-backdrop');
document.querySelector('#folder-actions-close').addEventListener('click', closeFolderActions);
document.addEventListener('keydown', (event) => {
  if (event.key === 'Escape' && !folderActionsBackdrop.hidden) {
    event.preventDefault();
    closeFolderActions();
  }
});

function closeFolderActions() {
  folderActionsBackdrop.hidden = true;
}

function openFolderActions(folderID) {
  const folder = dashboardFolders.find((item) => item.id === folderID);
  if (!folder) return;
  post({ type: 'action', action: 'overlay.focus' });
  document.querySelector('#folder-actions-title').textContent = folder.name;
  const folderApplications = folder.applicationIDs
    .map((id) => dashboardApplications.find((application) => application.id === id))
    .filter(Boolean);
  const actions = folderApplications.map((application) => {
    const button = document.createElement('button');
    button.className = 'control-action';
    button.dataset.action = 'folder.open-app';
    button.dataset.folder = folder.id;
    button.dataset.application = application.id;
    button.disabled = !application.isAvailable;
    const heading = document.createElement('span');
    heading.className = 'app-action-heading';
    if (application.iconDataURL) {
      const icon = document.createElement('img');
      icon.className = 'application-icon';
      icon.src = application.iconDataURL;
      icon.alt = '';
      heading.append(icon);
    } else {
      const fallback = document.createElement('i');
      fallback.className = 'application-icon fallback';
      fallback.textContent = application.name.slice(0, 2).toUpperCase();
      heading.append(fallback);
    }
    const title = document.createElement('span');
    title.textContent = application.name;
    heading.append(title);
    const detail = document.createElement('small');
    detail.textContent = !application.isAvailable
      ? 'Not installed on this Mac'
      : application.id === folder.defaultApplicationID ? 'Default for this folder' : 'Open this folder';
    button.append(heading, detail);
    return button;
  });
  const terminal = document.createElement('button');
  terminal.className = 'control-action';
  terminal.dataset.action = 'folder.open-terminal';
  terminal.dataset.folder = folder.id;
  const terminalTitle = document.createElement('span');
  terminalTitle.className = 'app-action-heading';
  const terminalIcon = document.createElement('i');
  terminalIcon.className = 'application-icon fallback terminal-icon';
  terminalIcon.textContent = '>_';
  const terminalName = document.createElement('span');
  terminalName.textContent = document.querySelector('#terminal-name').textContent;
  terminalTitle.append(terminalIcon, terminalName);
  const terminalDetail = document.createElement('small');
  terminalDetail.textContent = 'Open a terminal at this folder';
  terminal.append(terminalTitle, terminalDetail);
  document.querySelector('#folder-actions-list').replaceChildren(...actions, terminal);
  folderActionsBackdrop.hidden = false;
}

function runFolderPrimaryAction(folderID) {
  const folder = dashboardFolders.find((item) => item.id === folderID);
  if (!folder || folder.primaryAction === 'showMenu') {
    openFolderActions(folderID);
    return;
  }
  if (folder.primaryAction === 'terminal') {
    post({ type: 'action', action: 'folder.open-terminal', folder: folder.id });
    return;
  }
  if (!folder.defaultApplicationID) {
    openFolderActions(folderID);
    return;
  }
  post({
    type: 'action',
    action: folder.primaryAction === 'defaultApplicationAndTerminal' ? 'folder.open-recipe' : 'folder.open-app',
    folder: folder.id,
    application: folder.defaultApplicationID
  });
}

function renderWorkspaces(workspaces) {
  const list = document.querySelector('#workspace-nav');
  list.replaceChildren(...workspaces.map((workspace) => {
    const button = document.createElement('button');
    button.className = 'workspace-tab';
    button.dataset.workspace = workspace.id;
    button.style.setProperty('--workspace-color', workspace.color);
    const label = document.createElement('span');
    label.textContent = workspace.shortLabel;
    button.append(label, document.createTextNode(workspace.name));
    return button;
  }));
}

function activateWorkspace(workspaceID) {
  const selected = [...document.querySelectorAll('[data-workspace]')]
    .find((item) => item.dataset.workspace === workspaceID) || document.querySelector('[data-workspace]');
  if (!selected) return;
  document.querySelectorAll('[data-workspace]').forEach((item) => item.classList.toggle('active', item === selected));
  activeWorkspaceID = selected.dataset.workspace;
  const workspace = dashboardWorkspaces.find((item) => item.id === activeWorkspaceID);
  document.querySelector('#workspace-heading').textContent = `WORKSPACE / ${workspace?.name || ''}`.toUpperCase();
  if (workspace?.color) document.documentElement.style.setProperty('--violet', workspace.color);
  renderFolders(dashboardFolders.filter((folder) => folder.workspaceID === activeWorkspaceID));
}

function updateClock() {
  const now = new Date();
  document.querySelector('#clock').textContent = now.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
  document.querySelector('#date').textContent = now.toLocaleDateString([], { weekday: 'short', day: 'numeric', month: 'short' });
}
updateClock();
setInterval(updateClock, 1000);

function renderFolders(folders) {
  const list = document.querySelector('#folder-list');
  document.querySelector('#folder-count').textContent = `${folders.length} ${folders.length === 1 ? 'FOLDER' : 'FOLDERS'}`;
  if (!folders.length) {
    list.innerHTML = `
      <div class="workspace-empty">
        <strong>No folders in this workspace</strong>
        <small>Add one or more project folders to get started.</small>
        <button class="primary-action" data-action="folders.add">Add Folders</button>
      </div>`;
    return;
  }

  list.replaceChildren(...folders.map((folder) => {
    const card = document.createElement('div');
    card.className = 'project';
    const button = document.createElement('button');
    button.className = 'folder-primary';
    button.dataset.folderPrimary = folder.id;

    const icon = document.createElement('span');
    icon.className = 'project-icon';
    icon.style.backgroundColor = folder.color;
    icon.textContent = folder.icon;

    const details = document.createElement('span');
    const name = document.createElement('strong');
    name.textContent = folder.name;
    const path = document.createElement('small');
    path.textContent = folder.path;
    details.append(name, path);

    button.append(icon, details);
    const options = document.createElement('button');
    options.className = 'state clean folder-options';
    options.dataset.folderMenu = folder.id;
    options.textContent = 'OPTIONS';
    card.append(button, options);
    return card;
  }));
}

window.edgeDashboard = {
  dismissOverlays() {
    closeFolderActions();
    controlsBackdrop.hidden = true;
  },
  updateDriverHealth(health) {
    const dot = document.querySelector('#driver-dot');
    dot.className = `status-dot ${health.routingOpen ? 'active' : 'offline'}`;
    document.querySelector('#driver-state').textContent = `Touch driver · ${health.state}`;
    document.querySelector('#driver-message').textContent = health.message;
  },
  updateDisplayMessage(payload) {
    document.querySelector('#display-message').textContent = payload.message;
  },
  updateSystemMetrics(metrics) {
    document.querySelector('#cpu-value').textContent = `${metrics.cpuPercent}%`;
    document.querySelector('#cpu-meter').style.width = `${metrics.cpuPercent}%`;
    document.querySelector('#cpu-detail').textContent = metrics.cpuPercent < 70 ? 'Nominal load' : 'High load';
    document.querySelector('#memory-value').textContent = `${metrics.memoryPercent}%`;
    document.querySelector('#memory-meter').style.width = `${metrics.memoryPercent}%`;
    document.querySelector('#memory-detail').textContent = metrics.memoryDetail;
    document.querySelector('#uptime').textContent = metrics.uptime;
  },
  updatePreferences(preferences) {
    document.querySelector('#dashboard-title').textContent = preferences.dashboardTitle;
    document.querySelector('#editor-name').textContent = preferences.editorName;
    document.querySelector('#terminal-name').textContent = preferences.terminalName;
    dashboardApplications = preferences.applications;
    dashboardWorkspaces = preferences.workspaces;
    dashboardFolders = preferences.folders;
    renderWorkspaces(dashboardWorkspaces);
    const desiredWorkspace = dashboardWorkspaces.some((workspace) => workspace.id === activeWorkspaceID)
      ? activeWorkspaceID
      : preferences.startWorkspace;
    activateWorkspace(desiredWorkspace);
  },
  presentActionError(payload) {
    const toast = document.querySelector('#toast');
    toast.textContent = payload.message;
    toast.hidden = false;
    clearTimeout(window.edgeToastTimer);
    window.edgeToastTimer = setTimeout(() => { toast.hidden = true; }, 5000);
  }
};
