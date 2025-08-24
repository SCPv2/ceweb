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
 * Samsung Cloud Platform Object Storage 업로드 라우터
 * S3 호환 스토리지 업로드를 위한 API 엔드포인트
 */

const express = require('express');
const multer = require('multer');
const path = require('path');
const { getS3Service } = require('../s3Service');

const router = express.Router();

// Multer 메모리 저장소 설정 (S3 직접 업로드용)
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
 * 상품 이미지 업로드 (S3)
 * POST /api/s3/upload-product-image
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

        // S3 서비스 인스턴스 가져오기
        const s3Service = getS3Service();
        
        // 파일명 생성
        const fileName = s3Service.generateFileName(req.file.originalname, 'product_');
        
        console.log('상품 이미지 S3 업로드 시작:', {
            originalName: req.file.originalname,
            fileName: fileName,
            size: req.file.size,
            contentType: req.file.mimetype
        });

        // S3에 업로드
        const uploadResult = await s3Service.uploadProductImage(
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
                path: `/media/img/${fileName}`, // 웹에서 접근할 상대 경로
                url: uploadResult.publicUrl, // S3 Public URL
                publicUrl: uploadResult.publicUrl,
                uploadDate: uploadResult.uploadDate,
                etag: uploadResult.etag
            }
        });

    } catch (error) {
        console.error('상품 이미지 S3 업로드 오류:', error);
        
        res.status(500).json({
            success: false,
            message: error.message || '상품 이미지 업로드 중 오류가 발생했습니다.'
        });
    }
});

/**
 * 오디션 파일 업로드 (S3)
 * POST /api/s3/upload-audition-file
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

        // S3 서비스 인스턴스 가져오기
        const s3Service = getS3Service();
        
        // 파일명 생성
        const fileName = s3Service.generateFileName(req.file.originalname, 'audition_');
        
        console.log('오디션 파일 S3 업로드 시작:', {
            originalName: req.file.originalname,
            fileName: fileName,
            size: req.file.size,
            contentType: req.file.mimetype
        });

        // S3에 업로드
        const uploadResult = await s3Service.uploadAuditionFile(
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
                path: `/files/audition/${fileName}`, // 웹에서 접근할 상대 경로
                url: uploadResult.publicUrl, // S3 Public URL
                publicUrl: uploadResult.publicUrl,
                downloadUrl: uploadResult.publicUrl, // audition.html 호환성
                uploadDate: uploadResult.uploadDate,
                etag: uploadResult.etag
            }
        });

    } catch (error) {
        console.error('오디션 파일 S3 업로드 오류:', error);
        
        res.status(500).json({
            success: false,
            message: error.message || '오디션 파일 업로드 중 오류가 발생했습니다.'
        });
    }
});

/**
 * 파일 삭제 (S3)
 * DELETE /api/s3/delete-file/:type/:filename
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

        // S3 서비스 인스턴스 가져오기
        const s3Service = getS3Service();
        
        // S3 키 생성
        let key;
        if (type === 'product') {
            key = `${s3Service.credentials.folders.media}/${filename}`;
        } else {
            key = `${s3Service.credentials.folders.audition}/${filename}`;
        }
        
        console.log(`${type} 파일 S3 삭제 시작: ${key}`);

        // S3에서 삭제
        const deleteResult = await s3Service.deleteFile(key);

        res.json({
            success: true,
            message: deleteResult.message
        });

    } catch (error) {
        console.error('파일 S3 삭제 오류:', error);
        
        res.status(500).json({
            success: false,
            message: error.message || '파일 삭제 중 오류가 발생했습니다.'
        });
    }
});

/**
 * CORS 설정 
 * POST /api/s3/setup-cors
 */
router.post('/setup-cors', async (req, res) => {
    try {
        const s3Service = getS3Service();
        const result = await s3Service.setBucketCORS();
        
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
 * Presigned URL 생성
 * GET /api/s3/presigned-url/:type/:filename
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

        // S3 서비스 인스턴스 가져오기
        const s3Service = getS3Service();
        
        // S3 키 생성
        let key;
        if (type === 'product') {
            key = `${s3Service.credentials.folders.media}/${filename}`;
        } else {
            key = `${s3Service.credentials.folders.audition}/${filename}`;
        }
        
        console.log(`${type} 파일 Presigned URL 생성: ${key}, 만료시간: ${expiresIn}초`);

        // Presigned URL 생성
        const presignedUrl = await s3Service.getPresignedUrl(key, parseInt(expiresIn));

        res.json({
            success: true,
            message: 'Presigned URL이 성공적으로 생성되었습니다.',
            data: {
                filename: filename,
                type: type,
                key: key,
                presignedUrl: presignedUrl,
                expiresIn: parseInt(expiresIn),
                expiresAt: new Date(Date.now() + parseInt(expiresIn) * 1000).toISOString()
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
 * S3 서비스 상태 확인
 * GET /api/s3/status
 */
router.get('/status', (req, res) => {
    try {
        const s3Service = getS3Service();
        
        res.json({
            success: true,
            message: 'Samsung Cloud Platform Object Storage 서비스가 정상 작동 중입니다.',
            config: {
                bucketName: s3Service.bucketName,
                region: s3Service.credentials.region,
                publicEndpoint: s3Service.publicEndpoint,
                folders: s3Service.credentials.folders
            }
        });
    } catch (error) {
        console.error('S3 상태 확인 오류:', error);
        
        res.status(500).json({
            success: false,
            message: error.message || 'S3 서비스 상태 확인 중 오류가 발생했습니다.'
        });
    }
});

module.exports = router;