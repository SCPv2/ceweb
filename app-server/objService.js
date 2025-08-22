/**
 * Samsung Cloud Platform Object Storage Service (Object Storage Version)
 * S3 호환 스토리지를 위한 서비스 모듈 - Object Storage URL 생성 기능 포함
 */

const { S3Client, PutObjectCommand, DeleteObjectCommand, GetObjectCommand, PutBucketCorsCommand } = require('@aws-sdk/client-s3');
const { getSignedUrl } = require('@aws-sdk/s3-request-presigner');
const path = require('path');
const fs = require('fs');

class ObjectStorageService {
    constructor() {
        this.credentials = null;
        this.s3Client = null;
        this.bucketName = null;
        this.bucketString = null;
        this.publicEndpoint = null;
        this.privateEndpoint = null;
        
        this.loadCredentials();
        this.initS3Client();
    }

    /**
     * Object Storage 인증 정보 로드 (master_config.json에서 로드)
     */
    loadCredentials() {
        try {
            const masterConfigPath = path.join(__dirname, '../web-server/master_config.json');
            
            if (!fs.existsSync(masterConfigPath)) {
                throw new Error(`Master config file not found: ${masterConfigPath}`);
            }
            
            console.log('Loading Object Storage configuration from master_config.json...');
            const masterConfig = JSON.parse(fs.readFileSync(masterConfigPath, 'utf8'));
            
            this.credentials = {
                accessKeyId: masterConfig.object_storage.access_key_id,
                secretAccessKey: masterConfig.object_storage.secret_access_key,
                region: masterConfig.object_storage.region,
                bucketName: masterConfig.object_storage.bucket_name,
                bucketString: masterConfig.object_storage.bucket_string,
                privateEndpoint: masterConfig.object_storage.private_endpoint,
                publicEndpoint: masterConfig.object_storage.public_endpoint,
                folders: masterConfig.object_storage.folders
            };
            
            this.bucketName = this.credentials.bucketName;
            this.bucketString = this.credentials.bucketString;
            this.publicEndpoint = this.credentials.publicEndpoint;
            this.privateEndpoint = this.credentials.privateEndpoint;
            
            console.log(`✅ Master config loaded - Bucket: ${this.bucketName}, BucketString: ${this.bucketString}`);
            console.log(`   - Region: ${this.credentials.region}`);
            console.log(`   - Private Endpoint: ${this.privateEndpoint}`);
            console.log(`   - Public Endpoint: ${this.publicEndpoint}`);
            
        } catch (error) {
            console.error('❌ Object Storage 인증 정보 로드 실패:', error.message);
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
            
            console.log('✅ Samsung Cloud Platform Object Storage 클라이언트 초기화 완료');
        } catch (error) {
            console.error('❌ Object Storage 클라이언트 초기화 실패:', error.message);
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
                        'https://www.cesvc.net',
                        'https://cesvc.net',
                        'http://www.cesvc.net',
                        'http://cesvc.net',
                        'https://10.1.1.111',
                        'https://10.1.1.112',
                        'http://10.1.1.111',
                        'http://10.1.1.112',
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
     * Object Storage 퍼블릭 URL 생성
     * @param {string} key S3 키 (경로/파일명)
     * @returns {string} Object Storage 퍼블릭 URL
     */
    getObjectStoragePublicUrl(key) {
        return `${this.publicEndpoint}/${this.bucketString}:${this.bucketName}/${key}`;
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
            
            // Object Storage 퍼블릭 URL 생성
            const objectStorageUrl = this.getObjectStoragePublicUrl(key);
            
            console.log(`✅ 파일 업로드 성공: ${key}`);
            console.log(`   - Object Storage URL: ${objectStorageUrl}`);
            
            return {
                success: true,
                key: key,
                objectStorageUrl: objectStorageUrl,
                publicUrl: objectStorageUrl, // 호환성을 위해 동일한 값으로 설정
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
     * Presigned URL 생성 (파일 접근용) - 퍼블릭 엔드포인트 사용
     * @param {string} key S3 키 (경로/파일명)
     * @param {number} expiresIn 만료 시간 (초, 기본: 7일)
     * @returns {Promise<string>} Presigned URL
     */
    async getPresignedUrl(key, expiresIn = 7 * 24 * 60 * 60) {
        try {
            // Presigned URL 생성을 위한 별도 S3 클라이언트 (퍼블릭 엔드포인트 사용)
            const publicS3Client = new S3Client({
                region: this.credentials.region,
                endpoint: this.publicEndpoint, // 퍼블릭 엔드포인트 사용
                credentials: {
                    accessKeyId: this.credentials.accessKeyId,
                    secretAccessKey: this.credentials.secretAccessKey
                },
                forcePathStyle: true
            });

            const command = new GetObjectCommand({
                Bucket: this.bucketName,
                Key: key
            });
            
            const presignedUrl = await getSignedUrl(publicS3Client, command, { expiresIn });
            
            console.log(`✅ Presigned URL 생성 성공 (${key})`);
            console.log(`   - 퍼블릭 엔드포인트: ${this.publicEndpoint}`);
            console.log(`   - 만료시간: ${expiresIn}초`);
            
            return presignedUrl;
        } catch (error) {
            console.error(`❌ Presigned URL 생성 실패 (${key}):`, error.message);
            throw new Error(`Presigned URL 생성 실패: ${error.message}`);
        }
    }

    /**
     * Public URL 생성 (Object Storage 퍼블릭 URL)
     * @param {string} key S3 키 (경로/파일명)
     * @returns {string} Object Storage 퍼블릭 URL
     */
    getPublicUrl(key) {
        return this.getObjectStoragePublicUrl(key);
    }

    /**
     * 상품 이미지 Object Storage URL 생성
     * @param {string} fileName 파일명
     * @returns {string} Object Storage 퍼블릭 URL
     */
    getProductImageUrl(fileName) {
        const key = `${this.credentials.folders.media}/${fileName}`;
        return this.getObjectStoragePublicUrl(key);
    }

    /**
     * 오디션 파일 Object Storage URL 생성
     * @param {string} fileName 파일명
     * @returns {string} Object Storage 퍼블릭 URL
     */
    getAuditionFileUrl(fileName) {
        const key = `${this.credentials.folders.audition}/${fileName}`;
        return this.getObjectStoragePublicUrl(key);
    }

    /**
     * 기존 상대경로를 Object Storage URL로 변환
     * @param {string} relativePath 기존 상대경로 (예: ../media/img/bb_prod1.png)
     * @returns {string} Object Storage 퍼블릭 URL
     */
    convertRelativePathToObjectStorageUrl(relativePath) {
        if (!relativePath) return '';
        
        // ../media/img/ 또는 ../../media/img/ 패턴 처리
        if (relativePath.includes('/media/img/')) {
            const fileName = relativePath.split('/media/img/').pop();
            return this.getProductImageUrl(fileName);
        }
        
        // /files/audition/ 패턴 처리
        if (relativePath.includes('/files/audition/')) {
            const fileName = relativePath.split('/files/audition/').pop();
            return this.getAuditionFileUrl(fileName);
        }
        
        return relativePath; // 변환할 수 없는 경우 원본 반환
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

    /**
     * Object Storage 서비스 상태 확인
     * @returns {Promise<Object>} 서비스 상태
     */
    async getStatus() {
        try {
            // 간단한 연결 테스트를 위해 버킷 확인
            const status = {
                success: true,
                service: 'Samsung Cloud Platform Object Storage',
                bucket: `${this.bucketString}:${this.bucketName}`,
                endpoints: {
                    public: this.publicEndpoint,
                    private: this.privateEndpoint
                },
                region: this.credentials.region,
                folders: this.credentials.folders,
                timestamp: new Date().toISOString(),
                version: '2.0 (Object Storage)'
            };
            
            console.log('✅ Object Storage 서비스 상태 확인 완료');
            return status;
            
        } catch (error) {
            console.error('❌ Object Storage 서비스 상태 확인 실패:', error.message);
            return {
                success: false,
                service: 'Samsung Cloud Platform Object Storage',
                error: error.message,
                timestamp: new Date().toISOString()
            };
        }
    }
}

// 싱글톤 인스턴스 생성
let objectStorageServiceInstance = null;

/**
 * Object Storage 서비스 인스턴스 가져오기
 * @returns {ObjectStorageService} Object Storage 서비스 인스턴스
 */
function getObjectStorageService() {
    if (!objectStorageServiceInstance) {
        objectStorageServiceInstance = new ObjectStorageService();
    }
    return objectStorageServiceInstance;
}

module.exports = {
    ObjectStorageService,
    getObjectStorageService
};