# Push to New Repo: hunyuan-instruct-nf4-runpod-worker

All references in this repo have been updated from `s4v4nn4h_z_image_workflow_final.json` to `hunyuan-instruct-nf4-runpod-worker`.

## 1. Create the new repository on GitHub

- Open: **https://github.com/new?name=hunyuan-instruct-nf4-runpod-worker**
- Repository name: `hunyuan-instruct-nf4-runpod-worker`
- Leave it **empty** (do not add a README, .gitignore, or license)
- Click **Create repository**

## 2. Push this repo to the new remote

A remote named `hunyuan-repo` is already configured. Push your current branch:

```powershell
cd "c:\Users\jmend\Desktop\Github\s4v4nn4h_z_image_workflow_final.json"
git push -u hunyuan-repo main
```

If you use SSH:

```powershell
git remote set-url hunyuan-repo git@github.com:Jmendapara/hunyuan-instruct-nf4-runpod-worker.git
git push -u hunyuan-repo main
```

After this, the new repo will contain all current contents and the updated references.

## 3. (Optional) Make the new repo the default remote

```powershell
git remote rename origin old-repo
git remote rename hunyuan-repo origin
git push -u origin main
```

You can delete this file after you finish.
