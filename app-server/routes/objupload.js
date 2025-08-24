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

/**
 * Samsung Cloud Platform Object Storage 업로드 라우터 (Object Storage Version)
 * S3 호환 스토리지 업로드를 위한 API 엔드포인트 - Object Storage URL 생성 기능 포함
 */

const express = require('express');
const multer = require('multer');
const path = require('path');
const { getObjectStorageService } = require('../objService');

const router = express.Router();

// Multer 메모리 저장소 설정 (Object Storage 직접 업로드용)
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
        
        cb(null, true); // 모든 파일 타입 허용 (라우터별로 세부 필터링)
    }
});

// 상품 이미지 업로드용 필터
const productImageFilter = (req, file, cb) => {
    const allowedImageTypes = [
        'image/jpeg',
        'image/jpg', 
        'image/png',
        'image/gif',
        'image/webp'
    ];
    
    if (allowedImageTypes.includes(file.mimetype)) {
        cb(null, true);
    } else {
        cb(new Error(`상품 이미지는 JPG, PNG, GIF, WebP 파일만 업로드 가능합니다: ${file.mimetype}`));
    }
};

// 오디션 파일용 필터
const auditionFileFilter = (req, file, cb) => {
    const allowedAuditionTypes = [
        'application/pdf',
        'application/msword',
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'audio/mpeg',
        'audio/mp3',
        'video/mp4',
        'image/jpeg',
        'image/jpg',
        'image/png'
    ];
    
    if (allowedAuditionTypes.includes(file.mimetype)) {
        cb(null, true);
    } else {
        cb(new Error(`지원하지 않는 오디션 파일 형식입니다: ${file.mimetype}`));
    }
};

/**
 * 상품 이미지 업로드 (Object Storage)
 * POST /api/objupload/upload-product-image
 */
router.post('/upload-product-image', upload.single('file'), async (req, res) => {
    try {
        if (!req.file) {
            return res.status(400).json({
                success: false,
                message: '이미지 파일이 업로드되지 않았습니다.'
            });
        }

        // 상품 이미지 파일 타입 검증
        productImageFilter(req, req.file, (err) => {
            if (err) {
                return res.status(400).json({
                    success: false,
                    message: err.message
                });
            }
        });

        // Object Storage 서비스 인스턴스 가져오기
        const objectStorageService = getObjectStorageService();
        
        // 파일명 생성
        const fileName = objectStorageService.generateFileName(req.file.originalname, 'product_');
        
        console.log('상품 이미지 Object Storage 업로드 시작:', {
            originalName: req.file.originalname,
            fileName: fileName,
            size: req.file.size,
            contentType: req.file.mimetype
        });

        // Object Storage에 업로드
        const uploadResult = await objectStorageService.uploadProductImage(
            req.file.buffer,
            fileName,
            req.file.mimetype
        );

        res.json({
            success: true,
            message: '상품 이미지가 Samsung Cloud Platform Object Storage에 성공적으로 업로드되었습니다.',
            file: {
                id: fileName, // 파일명을 ID로 사용
                originalName: req.file.originalname,
                filename: fileName,
                size: req.file.size,
                type: req.file.mimetype,
                path: uploadResult.objectStorageUrl, // Object Storage URL 직접 사용
                url: uploadResult.objectStorageUrl, // Object Storage Public URL
                publicUrl: uploadResult.objectStorageUrl,
                objectStorageUrl: uploadResult.objectStorageUrl,
                uploadDate: uploadResult.uploadDate,
                etag: uploadResult.etag
            }
        });

    } catch (error) {
        console.error('상품 이미지 Object Storage 업로드 오류:', error);
        
        res.status(500).json({
            success: false,
            message: error.message || '상품 이미지 업로드 중 오류가 발생했습니다.'
        });
    }
});

/**
 * 오디션 파일 업로드 (Object Storage)
 * POST /api/objupload/upload-audition-file
 */
router.post('/upload-audition-file', upload.single('file'), async (req, res) => {
    try {
        if (!req.file) {
            return res.status(400).json({
                success: false,
                message: '파일이 업로드되지 않았습니다.'
            });
        }

        // 오디션 파일 타입 검증
        auditionFileFilter(req, req.file, (err) => {
            if (err) {
                return res.status(400).json({
                    success: false,
                    message: err.message
                });
            }
        });

        // Object Storage 서비스 인스턴스 가져오기
        const objectStorageService = getObjectStorageService();
        
        // 파일명 생성
        const fileName = objectStorageService.generateFileName(req.file.originalname, 'audition_');
        
        console.log('오디션 파일 Object Storage 업로드 시작:', {
            originalName: req.file.originalname,
            fileName: fileName,
            size: req.file.size,
            contentType: req.file.mimetype
        });

        // Object Storage에 업로드
        const uploadResult = await objectStorageService.uploadAuditionFile(
            req.file.buffer,
            fileName,
            req.file.mimetype
        );

        res.json({
            success: true,
            message: '오디션 파일이 Samsung Cloud Platform Object Storage에 성공적으로 업로드되었습니다.',
            file: {
                id: fileName, // 파일명을 ID로 사용
                originalName: req.file.originalname,
                filename: fileName,
                size: req.file.size,
                type: req.file.mimetype,
                path: uploadResult.objectStorageUrl, // Object Storage URL 직접 사용
                url: uploadResult.objectStorageUrl, // Object Storage Public URL
                publicUrl: uploadResult.objectStorageUrl,
                objectStorageUrl: uploadResult.objectStorageUrl,
                downloadUrl: uploadResult.objectStorageUrl, // audition.html 호환성
                uploadDate: uploadResult.uploadDate,
                etag: uploadResult.etag
            }
        });

    } catch (error) {
        console.error('오디션 파일 Object Storage 업로드 오류:', error);
        
        res.status(500).json({
            success: false,
            message: error.message || '오디션 파일 업로드 중 오류가 발생했습니다.'
        });
    }
});

/**
 * 파일 삭제 (Object Storage)
 * DELETE /api/objupload/delete-file/:type/:filename
 * type: 'product' | 'audition'
 */
router.delete('/delete-file/:type/:filename', async (req, res) => {
    try {
        const { type, filename } = req.params;
        
        if (!['product', 'audition'].includes(type)) {
            return res.status(400).json({
                success: false,
                message: '올바르지 않은 파일 타입입니다. (product 또는 audition만 허용)'
            });
        }

        // Object Storage 서비스 인스턴스 가져오기
        const objectStorageService = getObjectStorageService();
        
        // Object Storage 키 생성
        let key;
        if (type === 'product') {
            key = `${objectStorageService.credentials.folders.media}/${filename}`;
        } else {
            key = `${objectStorageService.credentials.folders.audition}/${filename}`;
        }
        
        console.log(`${type} 파일 Object Storage 삭제 시작: ${key}`);

        // Object Storage에서 삭제
        const deleteResult = await objectStorageService.deleteFile(key);

        res.json({
            success: true,
            message: deleteResult.message
        });

    } catch (error) {
        console.error('파일 Object Storage 삭제 오류:', error);
        
        res.status(500).json({
            success: false,
            message: error.message || '파일 삭제 중 오류가 발생했습니다.'
        });
    }
});

/**
 * CORS 설정 
 * POST /api/objupload/setup-cors
 */
router.post('/setup-cors', async (req, res) => {
    try {
        const objectStorageService = getObjectStorageService();
        const result = await objectStorageService.setBucketCORS();
        
        res.json(result);
    } catch (error) {
        console.error('CORS 설정 오류:', error);
        
        res.status(500).json({
            success: false,
            message: error.message || 'CORS 설정 중 오류가 발생했습니다.'
        });
    }
});

/**
 * Presigned URL 생성 (참고용, Object Storage에서는 퍼블릭 URL 직접 사용)
 * GET /api/objupload/presigned-url/:type/:filename
 * type: 'product' | 'audition'
 */
router.get('/presigned-url/:type/:filename', async (req, res) => {
    try {
        const { type, filename } = req.params;
        const { expiresIn = 3600 } = req.query; // 기본 1시간
        
        if (!['product', 'audition'].includes(type)) {
            return res.status(400).json({
                success: false,
                message: '올바르지 않은 파일 타입입니다. (product 또는 audition만 허용)'
            });
        }

        // Object Storage 서비스 인스턴스 가져오기
        const objectStorageService = getObjectStorageService();
        
        // Object Storage 키 생성
        let key;
        if (type === 'product') {
            key = `${objectStorageService.credentials.folders.media}/${filename}`;
        } else {
            key = `${objectStorageService.credentials.folders.audition}/${filename}`;
        }
        
        console.log(`${type} 파일 Presigned URL 생성: ${key}, 만료시간: ${expiresIn}초`);

        // Presigned URL 생성 (참고용)
        const presignedUrl = await objectStorageService.getPresignedUrl(key, parseInt(expiresIn));
        
        // Object Storage 퍼블릭 URL도 함께 제공
        const objectStorageUrl = objectStorageService.getObjectStoragePublicUrl(key);

        res.json({
            success: true,
            message: 'Presigned URL과 Object Storage URL이 성공적으로 생성되었습니다.',
            data: {
                filename: filename,
                type: type,
                key: key,
                presignedUrl: presignedUrl,
                objectStorageUrl: objectStorageUrl, // 권장 사용
                expiresIn: parseInt(expiresIn),
                expiresAt: new Date(Date.now() + parseInt(expiresIn) * 1000).toISOString(),
                recommended: 'objectStorageUrl' // 권장 URL 필드 표시
            }
        });

    } catch (error) {
        console.error('Presigned URL 생성 오류:', error);
        
        res.status(500).json({
            success: false,
            message: error.message || 'Presigned URL 생성 중 오류가 발생했습니다.'
        });
    }
});

/**
 * Object Storage 서비스 상태 확인
 * GET /api/objupload/status
 */
router.get('/status', async (req, res) => {
    try {
        const objectStorageService = getObjectStorageService();
        const status = await objectStorageService.getStatus();
        
        res.json({
            success: true,
            message: 'Samsung Cloud Platform Object Storage 서비스가 정상 작동 중입니다.',
            data: status
        });
    } catch (error) {
        console.error('Object Storage 상태 확인 오류:', error);
        
        res.status(500).json({
            success: false,
            message: error.message || 'Object Storage 서비스 상태 확인 중 오류가 발생했습니다.'
        });
    }
});

module.exports = router;