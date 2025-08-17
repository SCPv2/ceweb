/**
 * Samsung Cloud Platform Object Storage Service
 * S3 호환 스토리지를 위한 서비스 모듈
 */

const { S3Client, PutObjectCommand, DeleteObjectCommand, GetObjectCommand, PutBucketCorsCommand } = require('@aws-sdk/client-s3');
const { getSignedUrl } = require('@aws-sdk/s3-request-presigner');
const path = require('path');
const fs = require('fs');

class S3Service {
    constructor() {
        this.credentials = null;
        this.s3Client = null;
        this.bucketName = null;
        this.publicEndpoint = null;
        this.privateEndpoint = null;
        
        this.loadCredentials();
        this.initS3Client();
    }

    /**
     * S3 인증 정보 로드
     */
    loadCredentials() {
        try {
            const credentialsPath = path.join(__dirname, 'credentials.json');
            
            if (!fs.existsSync(credentialsPath)) {
                throw new Error(`S3 인증 파일을 찾을 수 없습니다: ${credentialsPath}`);
            }
            
            const credentialsData = fs.readFileSync(credentialsPath, 'utf8');
            this.credentials = JSON.parse(credentialsData);
            
            this.bucketName = this.credentials.bucketName;
            this.publicEndpoint = this.credentials.publicEndpoint;
            this.privateEndpoint = this.credentials.privateEndpoint;
            
            console.log('✅ Samsung Cloud Platform Object Storage 인증 정보 로드 완료');
            console.log(`   - 버킷: ${this.bucketName}`);
            console.log(`   - 리전: ${this.credentials.region}`);
            console.log(`   - Private Endpoint: ${this.privateEndpoint}`);
            console.log(`   - Public Endpoint: ${this.publicEndpoint}`);
            
        } catch (error) {
            console.error('❌ S3 인증 정보 로드 실패:', error.message);
            throw error;
        }
    }

    /**
     * S3 클라이언트 초기화
     */
    initS3Client() {
        try {
            this.s3Client = new S3Client({
                region: this.credentials.region,
                endpoint: this.privateEndpoint, // Private endpoint for upload/delete operations
                credentials: {
                    accessKeyId: this.credentials.accessKeyId,
                    secretAccessKey: this.credentials.secretAccessKey
                },
                forcePathStyle: true // Samsung Cloud Platform Object Storage requires path-style URLs
            });
            
            console.log('✅ Samsung Cloud Platform S3 클라이언트 초기화 완료');
        } catch (error) {
            console.error('❌ S3 클라이언트 초기화 실패:', error.message);
            throw error;
        }
    }

    /**
     * CORS 설정 (Samsung Cloud Platform Object Storage용)
     */
    async setBucketCORS() {
        const corsConfiguration = {
            CORSRules: [
                {
                    AllowedOrigins: [
                        'https://www.creative-energy.net',
                        'https://creative-energy.net',
                        'http://www.creative-energy.net',
                        'http://creative-energy.net',
                        '*' // 개발 환경용 - 운영에서는 제거 권장
                    ],
                    AllowedMethods: ['GET', 'HEAD'],
                    AllowedHeaders: ['*'],
                    MaxAgeSeconds: 3600,
                    ExposeHeaders: ['ETag']
                }
            ]
        };

        try {
            const command = new PutBucketCorsCommand({
                Bucket: this.bucketName,
                CORSConfiguration: corsConfiguration
            });

            await this.s3Client.send(command);
            console.log('✅ Samsung Cloud Platform Object Storage CORS 설정 완료');
            
            return {
                success: true,
                message: 'CORS 설정이 성공적으로 적용되었습니다.'
            };
        } catch (error) {
            console.error('❌ CORS 설정 실패:', error.message);
            return {
                success: false,
                message: `CORS 설정 실패: ${error.message}`
            };
        }
    }

    /**
     * 파일 업로드 (Private endpoint 사용)
     * @param {Buffer} fileBuffer 파일 데이터
     * @param {string} key S3 키 (경로/파일명)
     * @param {string} contentType MIME 타입
     * @param {Object} metadata 추가 메타데이터
     * @returns {Promise<Object>} 업로드 결과
     */
    async uploadFile(fileBuffer, key, contentType, metadata = {}) {
        try {
            const command = new PutObjectCommand({
                Bucket: this.bucketName,
                Key: key,
                Body: fileBuffer,
                ContentType: contentType,
                Metadata: metadata,
                // Public read access
                ACL: 'public-read'
            });

            const result = await this.s3Client.send(command);
            
            // Public URL 생성 (직접 접근 불가능하므로 참고용)
            const publicUrl = `${this.publicEndpoint}/${this.bucketName}/${key}`;
            
            console.log(`✅ 파일 업로드 성공: ${key}`);
            console.log(`   - Public URL (참고용): ${publicUrl}`);
            console.log(`   - Presigned URL은 별도 API로 요청 필요`);
            
            return {
                success: true,
                key: key,
                publicUrl: publicUrl,    // 직접 접근 불가능한 Public URL
                etag: result.ETag,
                uploadDate: new Date().toISOString(),
                size: fileBuffer.length,
                contentType: contentType
            };
            
        } catch (error) {
            console.error(`❌ 파일 업로드 실패 (${key}):`, error.message);
            throw new Error(`파일 업로드 실패: ${error.message}`);
        }
    }

    /**
     * 상품 이미지 업로드
     * @param {Buffer} fileBuffer 이미지 파일 데이터  
     * @param {string} fileName 파일명
     * @param {string} contentType MIME 타입
     * @returns {Promise<Object>} 업로드 결과
     */
    async uploadProductImage(fileBuffer, fileName, contentType) {
        const key = `${this.credentials.folders.media}/${fileName}`;
        
        return await this.uploadFile(fileBuffer, key, contentType, {
            'file-type': 'product-image',
            'upload-date': new Date().toISOString()
        });
    }

    /**
     * 오디션 파일 업로드
     * @param {Buffer} fileBuffer 파일 데이터
     * @param {string} fileName 파일명  
     * @param {string} contentType MIME 타입
     * @returns {Promise<Object>} 업로드 결과
     */
    async uploadAuditionFile(fileBuffer, fileName, contentType) {
        const key = `${this.credentials.folders.audition}/${fileName}`;
        
        return await this.uploadFile(fileBuffer, key, contentType, {
            'file-type': 'audition-file',
            'upload-date': new Date().toISOString()
        });
    }

    /**
     * 파일 삭제
     * @param {string} key S3 키 (경로/파일명)
     * @returns {Promise<Object>} 삭제 결과
     */
    async deleteFile(key) {
        try {
            const command = new DeleteObjectCommand({
                Bucket: this.bucketName,
                Key: key
            });

            await this.s3Client.send(command);
            
            console.log(`✅ 파일 삭제 성공: ${key}`);
            
            return {
                success: true,
                message: `파일이 삭제되었습니다: ${key}`
            };
            
        } catch (error) {
            console.error(`❌ 파일 삭제 실패 (${key}):`, error.message);
            throw new Error(`파일 삭제 실패: ${error.message}`);
        }
    }

    /**
     * Presigned URL 생성 (파일 접근용)
     * @param {string} key S3 키 (경로/파일명)
     * @param {number} expiresIn 만료 시간 (초, 기본: 7일)
     * @returns {Promise<string>} Presigned URL
     */
    async getPresignedUrl(key, expiresIn = 7 * 24 * 60 * 60) {
        try {
            const command = new GetObjectCommand({
                Bucket: this.bucketName,
                Key: key
            });
            
            return await getSignedUrl(this.s3Client, command, { expiresIn });
        } catch (error) {
            console.error(`❌ Presigned URL 생성 실패 (${key}):`, error.message);
            throw new Error(`Presigned URL 생성 실패: ${error.message}`);
        }
    }

    /**
     * Public URL 생성 (참고용 - 직접 접근 불가능할 수 있음)
     * @param {string} key S3 키 (경로/파일명)
     * @returns {string} Public URL
     */
    getPublicUrl(key) {
        return `${this.publicEndpoint}/${this.bucketName}/${key}`;
    }

    /**
     * 상품 이미지 Public URL 생성
     * @param {string} fileName 파일명
     * @returns {string} Public URL
     */
    getProductImageUrl(fileName) {
        const key = `${this.credentials.folders.media}/${fileName}`;
        return this.getPublicUrl(key);
    }

    /**
     * 오디션 파일 Public URL 생성
     * @param {string} fileName 파일명
     * @returns {string} Public URL  
     */
    getAuditionFileUrl(fileName) {
        const key = `${this.credentials.folders.audition}/${fileName}`;
        return this.getPublicUrl(key);
    }

    /**
     * 파일명 생성 (타임스탬프 + 랜덤)
     * @param {string} originalName 원본 파일명
     * @param {string} prefix 접두사 (예: 'product_', 'audition_')
     * @returns {string} 생성된 파일명
     */
    generateFileName(originalName, prefix = '') {
        const timestamp = Date.now();
        const random = Math.floor(Math.random() * 1000);
        const ext = path.extname(originalName);
        
        return `${prefix}${timestamp}_${random}${ext}`;
    }
}

// 싱글톤 인스턴스 생성
let s3ServiceInstance = null;

/**
 * S3 서비스 인스턴스 가져오기
 * @returns {S3Service} S3 서비스 인스턴스
 */
function getS3Service() {
    if (!s3ServiceInstance) {
        s3ServiceInstance = new S3Service();
    }
    return s3ServiceInstance;
}

module.exports = {
    S3Service,
    getS3Service
};