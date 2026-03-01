from fastapi import FastAPI, Depends, HTTPException
from sqlalchemy.orm import Session
from sqlalchemy import text
from pydantic import BaseModel
from typing import Optional
import os

from database import get_db, engine
import models

# 테이블 자동 생성
models.Base.metadata.create_all(bind=engine)

app = FastAPI(
    title="myapp-flab-prd API",
    description="FastAPI + Aurora MySQL on ECS",
    version="1.0.0"
)

# ─────────────────────────────────────────────
# Pydantic Schemas
# ─────────────────────────────────────────────
class ItemCreate(BaseModel):
    name: str
    description: Optional[str] = None

class ItemResponse(BaseModel):
    id: int
    name: str
    description: Optional[str]

    class Config:
        from_attributes = True

# ─────────────────────────────────────────────
# Health Check (ALB, ECS 헬스체크용)
# ─────────────────────────────────────────────
@app.get("/health")
def health_check(db: Session = Depends(get_db)):
    try:
        db.execute(text("SELECT 1"))
        return {
            "status": "healthy",
            "db": "connected",
            "env": os.getenv("APP_ENV", "local")
        }
    except Exception as e:
        raise HTTPException(status_code=503, detail=f"DB connection failed: {str(e)}")

# ─────────────────────────────────────────────
# Items CRUD API
# ─────────────────────────────────────────────
@app.get("/")
def root():
    return {"message": "Welcome to myapp-flab-prd API", "version": "1.0.0"}

@app.get("/items")
def get_items(db: Session = Depends(get_db)):
    items = db.query(models.Item).all()
    return {"items": items, "count": len(items)}

@app.get("/items/{item_id}")
def get_item(item_id: int, db: Session = Depends(get_db)):
    item = db.query(models.Item).filter(models.Item.id == item_id).first()
    if not item:
        raise HTTPException(status_code=404, detail="Item not found")
    return item

@app.post("/items", response_model=ItemResponse)
def create_item(item: ItemCreate, db: Session = Depends(get_db)):
    db_item = models.Item(name=item.name, description=item.description)
    db.add(db_item)
    db.commit()
    db.refresh(db_item)
    return db_item

@app.delete("/items/{item_id}")
def delete_item(item_id: int, db: Session = Depends(get_db)):
    item = db.query(models.Item).filter(models.Item.id == item_id).first()
    if not item:
        raise HTTPException(status_code=404, detail="Item not found")
    db.delete(item)
    db.commit()
    return {"message": f"Item {item_id} deleted"}