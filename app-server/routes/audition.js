/*
==============================================================================
Copyright (c) 2025 Stan H. All rights reserved.

This software and its source code are the exclusive property of Stan H.

Use is strictly limited to 2025 SCPv2 Advance training and education only.
Any reproduction, modification, distribution, or other use beyond this scope is
strictly prohibited without prior written permission from the copyright holder.

Unauthorized use may lead to legal action under applicable law.

Contact: ars4mundus@gmail.com
==============================================================================
*/

const express = require('express');
const multer = require('multer');
const path = require('path');
const fs = require('fs').promises;
const pool = require('../config/database');
const router = express.Router();

// 파일 저장 경로 설정 (App-Server에 저장)
const UPLOAD_PATH = '/home/rocky/ceweb/files/audition';
const PRODUCT_IMAGE_PATH = '/home/rocky/ceweb/media/img';

// 업로드 디렉토리 생성
async function ensureUploadDir() {
    try {
        await fs.access(UPLOAD_PATH);
    } catch {
        await fs.mkdir(UPLOAD_PATH, { recursive: true });
        console.log('Audition upload directory created:', UPLOAD_PATH);
    }
}

// 상품 이미지 디렉토리 생성
async function ensureProductImageDir() {
    try {
        await fs.access(PRODUCT_IMAGE_PATH);
    } catch {
        await fs.mkdir(PRODUCT_IMAGE_PATH, { recursive: true });
        console.log('Product image directory created:', PRODUCT_IMAGE_PATH);
    }
}

// Multer 설정
const storage = multer.diskStorage({
    destination: async (req, file, cb) => {
        await ensureUploadDir();
        cb(null, UPLOAD_PATH);
    },
    filename: (req, file, cb) => {
        // 고유한 파일명 생성 (타임스탬프 + 랜덤숫자 + 원본확장자)
        const timestamp = Date.now();
        const random = Math.floor(Math.random() * 1000);
        const ext = path.extname(file.originalname);
        const filename = `${timestamp}_${random}${ext}`;
        cb(null, filename);
    }
});

const upload = multer({
    storage: storage,
    limits: {
        fileSize: 50 * 1024 * 1024 // 50MB 제한
    },
    fileFilter: (req, file, cb) => {
        // 한글 파일명 인코딩 처리
        try {
            file.originalname = Buffer.from(file.originalname, 'latin1').toString('utf8');
        } catch (error) {
            console.log('파일명 인코딩 변환 실패, 원본 사용:', file.originalname);
        }
        
        // 허용된 파일 타입
        const allowedTypes = [
            'application/pdf',
            'application/msword',
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
            'audio/mpeg',
            'video/mp4',
            'image/jpeg',
            'image/png'
        ];
        
        if (allowedTypes.includes(file.mimetype)) {
            cb(null, true);
        } else {
            cb(new Error(`지원하지 않는 파일 형식입니다: ${file.mimetype}`));
        }
    }
});

// 파일 업로드 테이블 생성 (최초 실행시)
async function initAuditionTable() {
    try {
        const query = `
            CREATE TABLE IF NOT EXISTS audition_files (
                id SERIAL PRIMARY KEY,
                original_name VARCHAR(255) NOT NULL,
                stored_filename VARCHAR(255) NOT NULL,
                file_path VARCHAR(500) NOT NULL,
                file_size BIGINT NOT NULL,
                mime_type VARCHAR(100) NOT NULL,
                upload_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            );
            
            CREATE INDEX IF NOT EXISTS idx_audition_files_upload_date 
            ON audition_files(upload_date);
        `;
        
        await pool.query(query);
        console.log('Audition files table initialized');
    } catch (error) {
        console.error('Failed to initialize audition table:', error);
    }
}

// 서버 시작시 테이블 초기화
initAuditionTable();

/**
 * 파일 업로드
 * POST /api/audition/upload
 */
router.post('/upload', upload.single('file'), async (req, res) => {
    try {
        if (!req.file) {
            return res.status(400).json({
                success: false,
                message: '파일이 업로드되지 않았습니다.'
            });
        }

        // 데이터베이스에 파일 정보 저장
        const query = `
            INSERT INTO audition_files 
            (original_name, stored_filename, file_path, file_size, mime_type)
            VALUES ($1, $2, $3, $4, $5)
            RETURNING id, original_name, stored_filename, file_size, mime_type, upload_date
        `;
        
        const values = [
            req.file.originalname,
            req.file.filename,
            req.file.path,
            req.file.size,
            req.file.mimetype
        ];
        
        const result = await pool.query(query, values);
        const fileRecord = result.rows[0];
        
        res.json({
            success: true,
            message: '파일이 성공적으로 업로드되었습니다.',
            file: {
                id: fileRecord.id,
                originalName: fileRecord.original_name,
                filename: fileRecord.stored_filename,
                size: fileRecord.file_size,
                type: fileRecord.mime_type,
                uploadDate: fileRecord.upload_date,
                downloadUrl: `/files/audition/${fileRecord.stored_filename}`
            }
        });

    } catch (error) {
        console.error('File upload error:', error);
        
        // 업로드된 파일이 있다면 삭제
        if (req.file) {
            try {
                await fs.unlink(req.file.path);
            } catch (unlinkError) {
                console.error('Failed to delete uploaded file:', unlinkError);
            }
        }
        
        res.status(500).json({
            success: false,
            message: error.message || '파일 업로드 중 오류가 발생했습니다.'
        });
    }
});

/**
 * 파일 목록 조회
 * GET /api/audition/files
 */
router.get('/files', async (req, res) => {
    try {
        const query = `
            SELECT 
                id,
                original_name,
                stored_filename,
                file_size,
                mime_type,
                upload_date
            FROM audition_files 
            ORDER BY upload_date DESC
        `;
        
        const result = await pool.query(query);
        
        const files = result.rows.map(row => ({
            id: row.id,
            name: row.original_name,
            filename: row.stored_filename,
            size: row.file_size,
            type: row.mime_type,
            uploadDate: row.upload_date,
            downloadUrl: `/files/audition/${row.stored_filename}`
        }));
        
        res.json({
            success: true,
            files: files,
            count: files.length
        });

    } catch (error) {
        console.error('File list error:', error);
        res.status(500).json({
            success: false,
            message: '파일 목록 조회 중 오류가 발생했습니다.'
        });
    }
});

/**
 * 파일 다운로드
 * GET /api/audition/download/:id
 */
router.get('/download/:id', async (req, res) => {
    try {
        const fileId = req.params.id;
        
        // 데이터베이스에서 파일 정보 조회
        const query = `
            SELECT original_name, stored_filename, file_path, mime_type 
            FROM audition_files 
            WHERE id = $1
        `;
        
        const result = await pool.query(query, [fileId]);
        
        if (result.rows.length === 0) {
            return res.status(404).json({
                success: false,
                message: '파일을 찾을 수 없습니다.'
            });
        }
        
        const fileInfo = result.rows[0];
        const filePath = path.join(UPLOAD_PATH, fileInfo.stored_filename);
        
        // 파일 존재 확인
        try {
            await fs.access(filePath);
        } catch {
            return res.status(404).json({
                success: false,
                message: '파일이 존재하지 않습니다.'
            });
        }
        
        // 파일 다운로드 응답
        res.setHeader('Content-Disposition', `attachment; filename="${encodeURIComponent(fileInfo.original_name)}"`);
        res.setHeader('Content-Type', fileInfo.mime_type);
        res.sendFile(filePath);

    } catch (error) {
        console.error('File download error:', error);
        res.status(500).json({
            success: false,
            message: '파일 다운로드 중 오류가 발생했습니다.'
        });
    }
});

/**
 * 파일 삭제
 * DELETE /api/audition/delete/:id
 */
router.delete('/delete/:id', async (req, res) => {
    try {
        const fileId = req.params.id;
        
        // 데이터베이스에서 파일 정보 조회
        const selectQuery = `
            SELECT original_name, stored_filename, file_path 
            FROM audition_files 
            WHERE id = $1
        `;
        
        const selectResult = await pool.query(selectQuery, [fileId]);
        
        if (selectResult.rows.length === 0) {
            return res.status(404).json({
                success: false,
                message: '파일을 찾을 수 없습니다.'
            });
        }
        
        const fileInfo = selectResult.rows[0];
        const filePath = path.join(UPLOAD_PATH, fileInfo.stored_filename);
        
        // 파일 시스템에서 파일 삭제
        try {
            await fs.unlink(filePath);
        } catch (unlinkError) {
            console.error('Failed to delete file from filesystem:', unlinkError);
            // 파일이 이미 삭제되었을 수 있으므로 계속 진행
        }
        
        // 데이터베이스에서 파일 레코드 삭제
        const deleteQuery = `DELETE FROM audition_files WHERE id = $1`;
        await pool.query(deleteQuery, [fileId]);
        
        res.json({
            success: true,
            message: `파일이 삭제되었습니다: ${fileInfo.original_name}`
        });

    } catch (error) {
        console.error('File delete error:', error);
        res.status(500).json({
            success: false,
            message: '파일 삭제 중 오류가 발생했습니다.'
        });
    }
});

/**
 * 파일 정보 조회
 * GET /api/audition/info/:id  
 */
router.get('/info/:id', async (req, res) => {
    try {
        const fileId = req.params.id;
        
        const query = `
            SELECT 
                id,
                original_name,
                stored_filename,
                file_size,
                mime_type,
                upload_date
            FROM audition_files 
            WHERE id = $1
        `;
        
        const result = await pool.query(query, [fileId]);
        
        if (result.rows.length === 0) {
            return res.status(404).json({
                success: false,
                message: '파일을 찾을 수 없습니다.'
            });
        }
        
        const fileInfo = result.rows[0];
        
        res.json({
            success: true,
            file: {
                id: fileInfo.id,
                name: fileInfo.original_name,
                filename: fileInfo.stored_filename,
                size: fileInfo.file_size,
                type: fileInfo.mime_type,
                uploadDate: fileInfo.upload_date,
                downloadUrl: `/files/audition/${fileInfo.stored_filename}`
            }
        });

    } catch (error) {
        console.error('File info error:', error);
        res.status(500).json({
            success: false,
            message: '파일 정보 조회 중 오류가 발생했습니다.'
        });
    }
});

// 상품 이미지 업로드용 Multer 설정
const productImageStorage = multer.diskStorage({
    destination: async (req, file, cb) => {
        await ensureProductImageDir();
        cb(null, PRODUCT_IMAGE_PATH);
    },
    filename: (req, file, cb) => {
        // 상품 이미지 파일명 생성 (product_ + 타임스탬프 + 원본확장자)
        const timestamp = Date.now();
        const random = Math.floor(Math.random() * 1000);
        const ext = path.extname(file.originalname);
        const filename = `product_${timestamp}_${random}${ext}`;
        cb(null, filename);
    }
});

const productImageUpload = multer({
    storage: productImageStorage,
    limits: {
        fileSize: 10 * 1024 * 1024 // 10MB 제한 (상품 이미지는 더 작게)
    },
    fileFilter: (req, file, cb) => {
        // 한글 파일명 인코딩 처리
        try {
            file.originalname = Buffer.from(file.originalname, 'latin1').toString('utf8');
        } catch (error) {
            console.log('파일명 인코딩 변환 실패, 원본 사용:', file.originalname);
        }
        
        // 이미지 파일만 허용
        const allowedTypes = [
            'image/jpeg',
            'image/jpg', 
            'image/png'
        ];
        
        if (allowedTypes.includes(file.mimetype)) {
            cb(null, true);
        } else {
            cb(new Error(`상품 이미지는 JPG, PNG 파일만 업로드 가능합니다: ${file.mimetype}`));
        }
    }
});

/**
 * 상품 이미지 업로드 (관리자 페이지용)
 * POST /api/audition/upload-product-image
 */
router.post('/upload-product-image', productImageUpload.single('file'), async (req, res) => {
    try {
        if (!req.file) {
            return res.status(400).json({
                success: false,
                message: '이미지 파일이 업로드되지 않았습니다.'
            });
        }

        console.log('상품 이미지 업로드 완료:', {
            originalName: req.file.originalname,
            filename: req.file.filename,
            size: req.file.size,
            path: req.file.path
        });

        // 웹에서 접근 가능한 경로 생성
        const webPath = `/media/img/${req.file.filename}`;
        
        res.json({
            success: true,
            message: '상품 이미지가 성공적으로 업로드되었습니다.',
            file: {
                originalName: req.file.originalname,
                filename: req.file.filename,
                size: req.file.size,
                type: req.file.mimetype,
                path: webPath,
                url: webPath,
                uploadDate: new Date().toISOString()
            }
        });

    } catch (error) {
        console.error('Product image upload error:', error);
        
        // 업로드된 파일이 있다면 삭제
        if (req.file) {
            try {
                await fs.unlink(req.file.path);
            } catch (unlinkError) {
                console.error('Failed to delete uploaded product image:', unlinkError);
            }
        }
        
        res.status(500).json({
            success: false,
            message: error.message || '상품 이미지 업로드 중 오류가 발생했습니다.'
        });
    }
});

module.exports = router;