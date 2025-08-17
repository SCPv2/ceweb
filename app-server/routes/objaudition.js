const express = require('express');
const multer = require('multer');
const path = require('path');
const pool = require('../config/database');
const { getObjectStorageService } = require('../objService');
const router = express.Router();

// Object Storage 서비스 인스턴스
const objectStorageService = getObjectStorageService();

// 메모리 저장소 사용 (Object Storage로 직접 업로드)
const storage = multer.memoryStorage();

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

// 오디션 파일 테이블 생성 (Object Storage 버전)
async function initObjAuditionTable() {
    try {
        const query = `
            CREATE TABLE IF NOT EXISTS obj_audition_files (
                id SERIAL PRIMARY KEY,
                original_name VARCHAR(255) NOT NULL,
                stored_filename VARCHAR(255) NOT NULL,
                object_storage_key VARCHAR(500) NOT NULL,
                object_storage_url VARCHAR(1000) NOT NULL,
                file_size BIGINT NOT NULL,
                mime_type VARCHAR(100) NOT NULL,
                upload_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            );
            
            CREATE INDEX IF NOT EXISTS idx_obj_audition_files_upload_date 
            ON obj_audition_files(upload_date);
        `;
        
        await pool.query(query);
        console.log('Object Storage audition files table initialized');
    } catch (error) {
        console.error('Failed to initialize obj audition table:', error);
    }
}

// 서버 시작시 테이블 초기화
initObjAuditionTable();

/**
 * 파일 업로드 (Object Storage)
 * POST /api/objaudition/upload
 */
router.post('/upload', upload.single('file'), async (req, res) => {
    try {
        if (!req.file) {
            return res.status(400).json({
                success: false,
                message: '파일이 업로드되지 않았습니다.'
            });
        }

        // Object Storage에 고유 파일명 생성
        const filename = objectStorageService.generateFileName(req.file.originalname, 'audition_');
        
        // Object Storage에 파일 업로드
        const uploadResult = await objectStorageService.uploadAuditionFile(
            req.file.buffer,
            filename,
            req.file.mimetype
        );

        if (!uploadResult.success) {
            throw new Error('Object Storage 업로드 실패');
        }

        // 데이터베이스에 파일 정보 저장
        const query = `
            INSERT INTO obj_audition_files 
            (original_name, stored_filename, object_storage_key, object_storage_url, file_size, mime_type)
            VALUES ($1, $2, $3, $4, $5, $6)
            RETURNING id, original_name, stored_filename, object_storage_url, file_size, mime_type, upload_date
        `;
        
        const values = [
            req.file.originalname,
            filename,
            uploadResult.key,
            uploadResult.objectStorageUrl,
            req.file.size,
            req.file.mimetype
        ];
        
        const result = await pool.query(query, values);
        const fileRecord = result.rows[0];
        
        res.json({
            success: true,
            message: '파일이 Object Storage에 성공적으로 업로드되었습니다.',
            file: {
                id: fileRecord.id,
                originalName: fileRecord.original_name,
                filename: fileRecord.stored_filename,
                size: fileRecord.file_size,
                type: fileRecord.mime_type,
                uploadDate: fileRecord.upload_date,
                downloadUrl: fileRecord.object_storage_url,
                objectStorageUrl: fileRecord.object_storage_url
            }
        });

    } catch (error) {
        console.error('Object Storage file upload error:', error);
        
        res.status(500).json({
            success: false,
            message: error.message || '파일 업로드 중 오류가 발생했습니다.'
        });
    }
});

/**
 * 파일 목록 조회 (Object Storage)
 * GET /api/objaudition/files
 */
router.get('/files', async (req, res) => {
    try {
        const query = `
            SELECT 
                id,
                original_name,
                stored_filename,
                object_storage_url,
                file_size,
                mime_type,
                upload_date
            FROM obj_audition_files 
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
            downloadUrl: row.object_storage_url,
            objectStorageUrl: row.object_storage_url
        }));
        
        res.json({
            success: true,
            files: files,
            count: files.length
        });

    } catch (error) {
        console.error('Object Storage file list error:', error);
        res.status(500).json({
            success: false,
            message: '파일 목록 조회 중 오류가 발생했습니다.'
        });
    }
});

/**
 * 파일 다운로드 URL 제공 (Object Storage)
 * GET /api/objaudition/download/:id
 */
router.get('/download/:id', async (req, res) => {
    try {
        const fileId = req.params.id;
        
        // 데이터베이스에서 파일 정보 조회
        const query = `
            SELECT original_name, stored_filename, object_storage_url, object_storage_key
            FROM obj_audition_files 
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
        
        // Object Storage 퍼블릭 URL로 리다이렉트
        res.json({
            success: true,
            downloadUrl: fileInfo.object_storage_url,
            filename: fileInfo.original_name,
            message: 'Object Storage URL을 사용하여 다운로드하세요.'
        });

    } catch (error) {
        console.error('Object Storage file download error:', error);
        res.status(500).json({
            success: false,
            message: '파일 다운로드 URL 생성 중 오류가 발생했습니다.'
        });
    }
});

/**
 * 파일 삭제 (Object Storage)
 * DELETE /api/objaudition/delete/:id
 */
router.delete('/delete/:id', async (req, res) => {
    try {
        const fileId = req.params.id;
        
        // 데이터베이스에서 파일 정보 조회
        const selectQuery = `
            SELECT original_name, stored_filename, object_storage_key
            FROM obj_audition_files 
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
        
        // Object Storage에서 파일 삭제
        try {
            await objectStorageService.deleteFile(fileInfo.object_storage_key);
        } catch (deleteError) {
            console.error('Failed to delete file from Object Storage:', deleteError);
            // Object Storage에서 삭제 실패해도 DB 레코드는 삭제하도록 계속 진행
        }
        
        // 데이터베이스에서 파일 레코드 삭제
        const deleteQuery = `DELETE FROM obj_audition_files WHERE id = $1`;
        await pool.query(deleteQuery, [fileId]);
        
        res.json({
            success: true,
            message: `파일이 Object Storage에서 삭제되었습니다: ${fileInfo.original_name}`
        });

    } catch (error) {
        console.error('Object Storage file delete error:', error);
        res.status(500).json({
            success: false,
            message: '파일 삭제 중 오류가 발생했습니다.'
        });
    }
});

/**
 * 파일 정보 조회 (Object Storage)
 * GET /api/objaudition/info/:id  
 */
router.get('/info/:id', async (req, res) => {
    try {
        const fileId = req.params.id;
        
        const query = `
            SELECT 
                id,
                original_name,
                stored_filename,
                object_storage_url,
                file_size,
                mime_type,
                upload_date
            FROM obj_audition_files 
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
                downloadUrl: fileInfo.object_storage_url,
                objectStorageUrl: fileInfo.object_storage_url
            }
        });

    } catch (error) {
        console.error('Object Storage file info error:', error);
        res.status(500).json({
            success: false,
            message: '파일 정보 조회 중 오류가 발생했습니다.'
        });
    }
});

/**
 * Object Storage 서비스 상태 확인
 * GET /api/objaudition/status
 */
router.get('/status', async (req, res) => {
    try {
        const status = await objectStorageService.getStatus();
        
        // 데이터베이스 연결 상태도 확인
        const dbQuery = 'SELECT COUNT(*) as file_count FROM obj_audition_files';
        const dbResult = await pool.query(dbQuery);
        
        res.json({
            success: true,
            objectStorage: status,
            database: {
                connected: true,
                fileCount: parseInt(dbResult.rows[0].file_count)
            },
            timestamp: new Date().toISOString()
        });

    } catch (error) {
        console.error('Object Storage status check error:', error);
        res.status(500).json({
            success: false,
            message: 'Object Storage 상태 확인 중 오류가 발생했습니다.',
            error: error.message
        });
    }
});

module.exports = router;